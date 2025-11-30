//
//  DiskArsenal.swift
//
//  Copyright (c) 2024 Alexander Cohen. All rights reserved.
//

import Foundation
import os

/// A disk-based cache implementation with staleness and cost-based eviction.
///
/// `DiskArsenal` provides persistent caching by storing items as files on disk.
/// It supports two eviction strategies:
/// - **Staleness-based**: Removes items older than a specified time interval
/// - **Cost-based**: Removes oldest items when total size exceeds the limit
///
/// ## Features
///
/// - **Persistent Storage**: Items survive app restarts
/// - **Automatic Eviction**: Removes stale or excess items based on configuration
/// - **Lazy Cost Calculation**: Disk size is calculated asynchronously on initialization
/// - **Thread Safety**: All operations are isolated to ``ArsenalActor``
///
/// ## Storage Location
///
/// Items are stored in the app's Caches directory under a folder named after
/// the cache identifier. File names are sanitized to be filesystem-safe.
///
/// ## Usage
///
/// ```swift
/// let diskCache = DiskArsenal<MyItem>(
///     "com.myapp.cache",
///     maxStaleness: 86400,    // 1 day
///     costLimit: 1024 * 1024 * 500  // 500 MB
/// )
///
/// // Store an item
/// await diskCache.set(item, key: "my-key")
///
/// // Retrieve an item
/// if let cached = await diskCache.value(for: "my-key") {
///     // Use cached item
/// }
/// ```
@available(iOS 17.0, macOS 14.0, macCatalyst 17.0, watchOS 10.0, visionOS 1.0, tvOS 17.0, *)
@ArsenalActor public class DiskArsenal<T: ArsenalItem>: ArsenalImp {
    private let logger = Logger(subsystem: "com.bedroomcode.arsenal", category: "DiskArsenal")
    private let urlProvider: ArsenalURLProvider
    private let maxStaleness: TimeInterval
    private var costCalculationTask: Task<UInt64, Never>?

    /// The maximum total cost allowed before eviction occurs.
    public var costLimit: UInt64

    /// The current total cost of all cached items on disk.
    public private(set) var cost: UInt64

    /// The unique identifier for this cache instance.
    let identifier: String

    /// Creates a new disk cache with the specified configuration.
    ///
    /// - Parameters:
    ///   - identifier: A unique identifier used for the storage directory name.
    ///   - maxStaleness: The maximum age in seconds for cached items. Items older
    ///     than this are removed during purge. A value of `0` disables staleness-based eviction.
    ///   - costLimit: The maximum total size in bytes before eviction occurs.
    ///     A value of `0` disables cost-based eviction.
    init(_ identifier: String, maxStaleness: TimeInterval = 0, costLimit: UInt64 = 0) {
        self.identifier = identifier
        urlProvider = ArsenalURLProvider(identifier, fileManager: FileManager())
        self.maxStaleness = maxStaleness
        self.costLimit = costLimit
        cost = 0
        costCalculationTask = Task {
            self.calculateCost()
        }
    }

    /// Ensures the initial cost calculation has completed before proceeding.
    private func ensureCostCalculated() async {
        if let task = costCalculationTask {
            cost = await task.value
            costCalculationTask = nil
        }
    }

    /// Updates the cost limit and triggers eviction if necessary.
    ///
    /// - Parameter to: The new cost limit in bytes.
    public func update(costLimit to: UInt64) async {
        ArsenalActor.assertIsolated()

        costLimit = to
        purgeUnowned()
        await purge()
    }

    /// Stores or removes an item on disk.
    ///
    /// When storing, the item is serialized using its `toData()` method and
    /// written to a file. After storing, the cache may purge items if limits are exceeded.
    ///
    /// - Parameters:
    ///   - value: The item to store, or `nil` to remove the existing item.
    ///   - key: The unique key to associate with the item.
    public func set(_ value: T?, key: String) async {
        ArsenalActor.assertIsolated()
        await ensureCostCalculated()

        guard var url = urlProvider.url(for: key) else {
            return
        }
        if let data = value?.toData() {
            do {
                // Get old file size before overwriting
                let oldSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0

                try data.write(to: url)

                // Write succeeded - adjust cost (subtract old, add new)
                if oldSize > 0 {
                    cost -= UInt64(oldSize)
                }
                // Clear cached resource values to get accurate new file size
                url.removeCachedResourceValue(forKey: .fileSizeKey)
                let newSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                if newSize > 0 {
                    cost += UInt64(newSize)
                }
                await purge()
            } catch {
                logger.error("Error writing to disk: \(error)")
            }
        } else {
            deleteItem(at: url)
        }
    }

    /// Retrieves an item from disk.
    ///
    /// The item is deserialized using the type's `from(data:)` method.
    ///
    /// - Parameter key: The key associated with the item.
    /// - Returns: The cached item, or `nil` if not found or deserialization fails.
    public func value(for key: String) -> T? {
        ArsenalActor.assertIsolated()

        guard let url = urlProvider.url(for: key), let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return nil
        }
        return T.from(data: data) as? T
    }

    /// Checks if an item exists on disk.
    ///
    /// - Parameter key: The key to check.
    /// - Returns: `true` if a file exists for the key, `false` otherwise.
    public func contains(_ key: String) -> Bool {
        ArsenalActor.assertIsolated()

        if let url = urlProvider.url(for: key) {
            return urlProvider.fileManager.fileExists(atPath: url.path())
        }
        return false
    }

    /// No-op for disk cache. Disk items don't have weak reference semantics.
    public func purgeUnowned() {}

    /// Purges items based on staleness and cost limits.
    ///
    /// This method:
    /// 1. Removes items older than `maxStaleness` (if configured)
    /// 2. Removes oldest items until under `costLimit` (if configured)
    ///
    /// Items are sorted by modification date, with oldest items removed first.
    public func purge() async {
        ArsenalActor.assertIsolated()

        guard maxStaleness > 0 || costLimit > 0 else {
            return
        }

        await ensureCostCalculated()

        guard let baseURL = urlProvider.cacheURL else {
            return
        }

        guard let urls = try? urlProvider.fileManager.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey], options: .skipsHiddenFiles) else {
            return
        }

        // sort URLs newest to oldest
        var sortedUrls = urls.sorted { url1, url2 in
            guard let date1 = try? url1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  let date2 = try? url2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            else {
                return false
            }
            return date1.compare(date2) == .orderedDescending
        }

        // Purge based on date
        if maxStaleness > 0 {
            let now = Date()
            var itemsWithoutDates: [URL] = []
            while let url = sortedUrls.popLast() {
                guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else {
                    // Keep items without valid dates for cost-based purge
                    itemsWithoutDates.append(url)
                    continue
                }

                // Item is too young, since we're sorted we can bail
                guard now.timeIntervalSince1970 - date.timeIntervalSince1970 > maxStaleness else {
                    // Put the item back so it can be considered for cost-based purge
                    sortedUrls.append(url)
                    break
                }

                // We now know we need to delete the item
                deleteItem(at: url)
            }
            // Add back items without dates so they can be considered for cost-based purge
            sortedUrls.append(contentsOf: itemsWithoutDates)
        }

        // Purge based on cost
        if costLimit > 0 {
            while cost > costLimit, let url = sortedUrls.popLast() {
                guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 else {
                    continue
                }

                // We now know we need to delete the item
                deleteItem(at: url)
            }
        }
    }

    /// Removes all items from the disk cache.
    public func clear() async {
        ArsenalActor.assertIsolated()
        await ensureCostCalculated()

        guard let baseURL = urlProvider.cacheURL else {
            return
        }
        if let urls = try? urlProvider.fileManager.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: nil) {
            for url in urls {
                deleteItem(at: url)
            }
        }
    }

    // MARK: - Private Methods

    private func deleteItem(at url: URL) {
        ArsenalActor.assertIsolated()

        // Read size separately so we can still adjust cost even if this fails
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        do {
            try urlProvider.fileManager.removeItem(at: url)
            if size > 0 {
                cost -= UInt64(size)
            }
        } catch {
            logger.error("Error deleting from disk: \(error)")
        }
    }

    private func calculateCost() -> UInt64 {
        ArsenalActor.assertIsolated()

        guard let baseURL = urlProvider.cacheURL else {
            return 0
        }

        guard let urls = try? urlProvider.fileManager.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: [.fileSizeKey], options: .skipsHiddenFiles) else {
            return 0
        }

        return urls.reduce(0) { cost, url in
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 {
                return cost + UInt64(size)
            }
            return cost
        }
    }
}

// MARK: - ArsenalURLProvider

/// A helper class that manages file URLs for disk-based caching.
///
/// This class handles:
/// - Creating the cache directory in the app's Caches folder
/// - Sanitizing keys to be valid file names
/// - Generating URLs for cache items
@available(iOS 17.0, macOS 14.0, macCatalyst 17.0, watchOS 10.0, visionOS 1.0, tvOS 17.0, *)
class ArsenalURLProvider {
    /// The identifier used for the cache directory.
    let identifier: String

    /// An optional prefix added to the directory name.
    let prefix: String

    /// The file manager used for file operations.
    let fileManager: FileManager

    /// Creates a new URL provider.
    ///
    /// - Parameters:
    ///   - identifier: The identifier for the cache directory.
    ///   - prefix: An optional prefix for the directory name. Defaults to empty.
    ///   - fileManager: The file manager to use. Defaults to a new instance.
    init(_ identifier: String, prefix: String = "", fileManager: FileManager) {
        self.identifier = identifier
        self.prefix = prefix
        self.fileManager = fileManager
    }

    /// The base URL for the cache directory.
    ///
    /// Creates the directory if it doesn't exist. Returns `nil` if the
    /// Caches directory cannot be accessed.
    var cacheURL: URL? {
        if let baseURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first?.appending(component: sanitizedIdentifier) {
            try? fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
            return baseURL
        }
        return nil
    }

    private lazy var sanitizedIdentifier: String = sanitize(prefix.isEmpty ? identifier : prefix + "." + identifier)
    private lazy var allowedCharacterSet: CharacterSet = .alphanumerics.union(CharacterSet(charactersIn: "._-"))

    /// Sanitizes a string to be a valid file name.
    ///
    /// - Parameter key: The string to sanitize.
    /// - Returns: A filesystem-safe version of the string.
    func sanitize(_ key: String) -> String {
        key.addingPercentEncoding(withAllowedCharacters: allowedCharacterSet) ?? key
    }

    /// Returns the file URL for a cache key.
    ///
    /// - Parameter key: The cache key.
    /// - Returns: The URL where the item should be stored, or `nil` if unavailable.
    func url(for key: String) -> URL? {
        cacheURL?.appending(component: sanitize(key))
    }
}
