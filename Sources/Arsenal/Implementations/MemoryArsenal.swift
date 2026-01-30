//
//  MemoryArsenal.swift
//
//  Copyright (c) 2024 Alexander Cohen. All rights reserved.
//

import Darwin
import Foundation
import os

/// An in-memory cache implementation with LRU (Least Recently Used) eviction.
///
/// `MemoryArsenal` provides fast, in-memory caching with automatic eviction
/// when the cache exceeds its cost limit. Items are evicted based on their
/// last access time, with the least recently accessed items removed first.
///
/// ## Features
///
/// - **LRU Eviction**: Automatically removes least recently used items when cost limit is exceeded
/// - **Weak Reference Purging**: Can detect and remove items no longer referenced elsewhere
/// - **Thread Safety**: All operations are isolated to ``ArsenalActor``
///
/// ## Usage
///
/// ```swift
/// let memoryCache = MemoryArsenal<MyItem>(costLimit: 1024 * 1024 * 100) // 100 MB
///
/// // Store an item
/// await memoryCache.set(item, key: "my-key")
///
/// // Retrieve an item (updates its access time)
/// if let cached = await memoryCache.value(for: "my-key") {
///     // Use cached item
/// }
/// ```
@available(iOS 17.0, macOS 14.0, macCatalyst 17.0, watchOS 10.0, visionOS 1.0, tvOS 17.0, *)
@ArsenalActor @Observable public class MemoryArsenal<T: ArsenalItem>: ArsenalImp {
    private let logger = Logger(subsystem: "com.bedroomcode.arsenal", category: "MemoryArsenal")

    /// Creates a new in-memory cache with the specified cost limit.
    ///
    /// - Parameter costLimit: The maximum total cost of items before eviction occurs.
    ///   A value of `0` means no limit. Defaults to `0`.
    init(costLimit: UInt64 = 0) {
        self.costLimit = costLimit
    }

    /// Updates the cost limit and triggers eviction if necessary.
    ///
    /// If the new limit is lower than the current cost, items will be
    /// evicted until the cache is within the new limit.
    ///
    /// - Parameter to: The new cost limit.
    public func update(costLimit to: UInt64) {
        ArsenalActor.assertIsolated()

        costLimit = to
        purgeUnowned()
        purge()
    }

    /// Stores or removes an item in the cache.
    ///
    /// When storing an item, if an item with the same key exists, it is replaced.
    /// After storing, the cache may purge items if the cost limit is exceeded.
    ///
    /// - Parameters:
    ///   - value: The item to store, or `nil` to remove the existing item.
    ///   - key: The unique key to associate with the item.
    public func set(_ value: T?, key: String) {
        ArsenalActor.assertIsolated()

        // Get old cost if exists (single lookup)
        let oldCost = cache[key]?.cost ?? 0

        if let img = value {
            let item = MemoryItem(key: key, value: img)
            cache[key] = item
            cost = cost - oldCost + item.cost
        } else {
            cache[key] = nil
            cost -= oldCost
        }
        purge()
    }

    /// Retrieves an item from the cache and updates its access time.
    ///
    /// Accessing an item updates its timestamp, making it less likely to be
    /// evicted during LRU purging.
    ///
    /// - Parameter key: The key associated with the item.
    /// - Returns: The cached item, or `nil` if not found.
    public func value(for key: String) -> T? {
        ArsenalActor.assertIsolated()

        guard var item = cache[key] else { return nil }

        item.updateTimestamp()
        cache[key] = item
        return item.value
    }

    /// Checks if an item exists in the cache.
    ///
    /// - Parameter key: The key to check.
    /// - Returns: `true` if an item with the key exists, `false` otherwise.
    public func contains(_ key: String) -> Bool {
        ArsenalActor.assertIsolated()

        return cache[key] != nil
    }

    /// Purges items that are no longer referenced elsewhere in the application.
    ///
    /// This method temporarily converts all cached items to weak references.
    /// Items that are only held by the cache (and not referenced elsewhere)
    /// will be deallocated and removed from the cache.
    ///
    /// This is useful for releasing memory when cached items are no longer
    /// being used by the application.
    public func purgeUnowned() {
        ArsenalActor.assertIsolated()

        // Convert items to weak references - items not referenced
        // elsewhere will be deallocated when we clear the cache.
        // Then rebuild with only the surviving items.

        logger.debug(
            "Purge unowned: trying to purge \(self.cache.count) items using \(self.cost) in cost"
        )

        let weakItems = cache.values.map { $0.weakify() }
        cache.removeAll()

        // Single pass: filter valid items, rebuild cache, and sum cost
        var newCost: UInt64 = 0
        for weakItem in weakItems {
            if let strongItem = weakItem.strongify() {
                cache[strongItem.key] = strongItem
                newCost += strongItem.cost
            }
        }
        cost = newCost

        logger.debug("After purge we have \(self.cache.count) items using \(self.cost) in cost")
    }

    /// Purges items using LRU eviction until the cache is within its cost limit.
    ///
    /// Items are sorted by their last access time, and the least recently
    /// accessed items are removed first until the total cost is below the limit.
    public func purge() {
        ArsenalActor.assertIsolated()

        // check our limits again in case we're
        // good after removing non-referenced items.
        guard costLimit > 0, cost > costLimit else {
            return
        }

        // Sort by timestamp descending (most recent first), so popLast() gives oldest
        var sorted = cache.values.sorted { $0.timestamp > $1.timestamp }

        while cost > costLimit, let item = sorted.popLast() {
            cache[item.key] = nil
            cost -= item.cost
        }
    }

    /// Removes all items from the cache.
    public func clear() {
        ArsenalActor.assertIsolated()

        cache = [:]
        cost = 0
    }

    // MARK: - Private Types

    private struct MemoryItem {
        let key: String
        let value: T
        let cost: UInt64
        var timestamp: UInt64

        init(key: String, value: T) {
            self.key = key
            self.value = value
            cost = value.cost
            timestamp = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        }

        init(key: String, value: T, cost: UInt64, timestamp: UInt64) {
            self.key = key
            self.value = value
            self.cost = cost
            self.timestamp = timestamp
        }

        mutating func updateTimestamp() {
            timestamp = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        }

        func weakify() -> MemoryWeakItem {
            MemoryWeakItem(key: key, value: value, cost: cost, timestamp: timestamp)
        }
    }

    private struct MemoryWeakItem {
        let key: String
        weak var value: T?
        let cost: UInt64
        let timestamp: UInt64

        init(key: String, value: T, cost: UInt64, timestamp: UInt64) {
            self.key = key
            self.value = value
            self.cost = cost
            self.timestamp = timestamp
        }

        func strongify() -> MemoryItem? {
            guard let val = value else {
                return nil
            }
            return MemoryItem(key: key, value: val, cost: cost, timestamp: timestamp)
        }
    }

    // MARK: - Properties

    private var cache: [String: MemoryItem] = [:]

    /// The current total cost of all cached items.
    public private(set) var cost: UInt64 = 0

    /// The maximum total cost allowed before eviction occurs.
    public var costLimit: UInt64
}
