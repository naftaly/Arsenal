//
//  Arsenal.swift
//
//  Copyright (c) 2024 Alexander Cohen. All rights reserved.
//

import Foundation

/// Arsenal is a simple implementation of a caching system that handles
/// in memory as well as on disk cache.
///
/// The memory cache has a weight limit in bytes which when exceeded will
/// start purging items by oldest access order (LRU) until the weight limit is not exceeded.
///
/// The disk cache has a max staleness value which when exceeded will
/// purge items oldest first until no items exceeed the max staleness.
///
/// Arsenal is observable in order to be able to pass it in the environment if needed.
///
/// Cache is thread safe and isolated to the @ArsenalActor.
///

@available(iOS 17.0, macOS 14.0, macCatalyst 17.0, watchOS 10.0, visionOS 1.0, *)
public protocol ArsenalItem : AnyObject {
    func toData() -> Data?
    static func from(data: Data) -> ArsenalItem?
    var cost: UInt64 { get }
}

@available(iOS 17.0, macOS 14.0, macCatalyst 17.0, watchOS 10.0, visionOS 1.0, *)
@ArsenalActor @Observable final public class Arsenal<T: ArsenalItem> : Sendable {
    
    public enum ResourceType {
        case memory
        case disk
    }
    
    /// String used to identify this Arsenal.
    let identifier: String
    
    /// Creates a new cache with default limits for disk and memory.
    /// 500 MB of memory limit.
    /// 1 day of max staleness.
    init(_ identifier: String, costLimit: UInt64 = UInt64(5e+8), maxStaleness: TimeInterval = 86400) {
        self.identifier = identifier
        self.resources = [
            .memory: MemoryArsenal<T>(costLimit: costLimit),
            .disk: DiskArsenal<T>(identifier, maxStaleness: maxStaleness),
        ]
    }
    
    /// Sets a cached item.
    /// Passing nil as a value will remove the item from cache.
    public func set(_ value: T?, key: String, types: Set<ResourceType> = [.memory, .disk]) async {
        types.forEach { type in
            (resources[type])?.set(value, key: key)
        }
    }
    
    public func set(_ value: T?, key: URL, types: Set<ResourceType> = [.memory, .disk]) async {
        await set(value, key: key.absoluteString, types: types)
    }
    
    /// Retrieve a cache item.
    /// The cache will check in memory first, then disk.
    public func value(for key: String) async -> T? {
        if let val = memoryResource?.value(for: key) {
            return val
        }
        if let val: T = diskResource?.value(for: key) {
            memoryResource?.set(val, key: key)
            return val
        }
        return nil
    }
    
    public func value(for key: URL) async -> T? {
        await value(for: key.absoluteString)
    }
    
    /// Updates the cost limits.
    /// This can cause a purge if the new weight limit is below usage.
    public func update(costLimit: UInt64, for types: Set<ResourceType> = [.memory]) async {
        for type in types {
            (resources[type])?.update(costLimit: costLimit)
        }
    }

    /// Purges memory and disk caches based on their limits.
    public func purge(_ types: Set<ResourceType> = [.memory, .disk]) async {
        for type in types {
            (resources[type])?.purge()
        }
    }
    
    /// Purges in memory caches of unreferenced items.
    public func purgeUnowned(_ types: Set<ResourceType> = [.memory, .disk]) async {
        for type in types {
            (resources[type])?.purgeUnowned()
        }
    }
    
    /// Removes all items from memory and disk cache.
    public func clear(_ types: Set<ResourceType> = [.memory, .disk]) async {
        for type in types {
            (resources[type])?.clear()
        }
    }
    
    /// Private resources + getters
    private var memoryResource: (any ArsenalImp<T>)? {
        return resources[.memory]
    }
    private var diskResource: (any ArsenalImp<T>)? {
        return resources[.disk]
    }
    private var resources: [ResourceType: any ArsenalImp<T>]
}

/// A global actor for the Arsenal, use as `@ArsenalActor`.
@available(iOS 17.0, macOS 14.0, macCatalyst 17.0, watchOS 10.0, visionOS 1.0, *)
@globalActor public struct ArsenalActor {
    public actor ActorType { }
    public static let shared: ActorType = ActorType()
}

#if canImport(UIKit)
import UIKit

/// An extension to UIImage that supports `ArsenalItem`
@available(iOS 17.0, macOS 14.0, macCatalyst 17.0, watchOS 10.0, visionOS 1.0, *)
extension UIImage: ArsenalItem {
    public func toData() -> Data? {
        return jpegData(compressionQuality: 1)
    }
    public static func from(data: Data) -> ArsenalItem? {
        return UIImage(data: data)
    }
    public var cost: UInt64 {
        // I'm assuming any image we use is ARGB
        // or some other simple form of RGB with 4 bytes per pixel,
        // so i'm not even accounting for it.
        return UInt64(size.width * size.height)
    }
}

#endif

#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit

/// Use as `@Environment(\.imageCache) var imageCache`

@available(iOS 17.0, macOS 14.0, macCatalyst 17.0, watchOS 10.0, visionOS 1.0, *)
struct ImageArsenalKey: EnvironmentKey {
    @ArsenalActor static var defaultValue: Arsenal<UIImage> = Arsenal<UIImage>("com.bedroomcode.image.arsenal")
}

@available(iOS 17.0, macOS 14.0, macCatalyst 17.0, watchOS 10.0, visionOS 1.0, *)
extension EnvironmentValues {
    public var imageArsenal: Arsenal<UIImage> {
        get { self[ImageArsenalKey.self] }
    }
}

#endif

// MARK: -
// MARK: Private
// Disk and Image internal Arsenal implementations from here on.

@available(iOS 17.0, macOS 14.0, macCatalyst 17.0, watchOS 10.0, visionOS 1.0, *)
@ArsenalActor fileprivate protocol ArsenalImp<T> : Sendable {
    associatedtype T
    
    func set(_ value: T?, key: String)
    func value(for key: String) -> T?
    
    func update(costLimit to: UInt64)
    func purge()
    func purgeUnowned()
    func clear()
}

@available(iOS 17.0, macOS 14.0, macCatalyst 17.0, watchOS 10.0, visionOS 1.0, *)
@ArsenalActor fileprivate class MemoryArsenal<T: ArsenalItem> : ArsenalImp, @unchecked Sendable {
    
    init(costLimit: UInt64 = 0) {
        self.costLimit = costLimit
    }
    
    public func update(costLimit to: UInt64) {
        ArsenalActor.assertIsolated()
        
        costLimit = to
        purgeUnowned()
        purge()
    }
    
    public func set(_ value: T?, key: String) {
        ArsenalActor.assertIsolated()
        
        if let img = cache[key] {
            usedCost -= img.cost
            cache[key] = nil
        }
        
        if let img = value {
            let item = MemoryItem(key: key, value: img)
            cache[key] = item
            usedCost += item.cost
        }
        purge()
    }
    
    public func value(for key: String) -> T? {
        ArsenalActor.assertIsolated()
        
        // update the last accessed date to ensure purges are correctly ordered
        cache[key]?.updateTimestamp()
        return cache[key]?.value
    }
    
    public func contains(_ key: String) -> Bool {
        ArsenalActor.assertIsolated()
        
        return cache[key] != nil
    }
    
    public func purgeUnowned() {
        ArsenalActor.assertIsolated()
        
        // this make all items weak
        // by doing so, all items that aren't
        // referenced anywhere will be nilled out
        // then we recreate the cache with what
        // is really owned.
        
        print("Purge unowned")
        print("trying to purge \(cache.count) items using \(usedCost) in cost")
        
        let weakItems = cache.values.map { $0.weakify() }
        cache = [:]
        usedCost = 0
        let strongItems = weakItems.compactMap { $0.strongify() }
        usedCost = strongItems.reduce(0) { $0 + $1.cost }
        strongItems.forEach { cache[$0.key] = $0 }
        
        print("After purge we have \(cache.count) items using \(usedCost) in cost")
    }
    
    public func purge() {
        ArsenalActor.assertIsolated()
        
        // check our limits again in case we're
        // good after removing non-referenced items.
        guard costLimit > 0 && usedCost >= costLimit else {
            return
        }
        
        // least recently accessed first (LRU)
        var sorted = cache.values.sorted { item1, item2 in
            item1.timestamp > item2.timestamp
        }
        
        while !sorted.isEmpty && usedCost >= costLimit {
            guard let item = sorted.first else {
                break
            }
            
            sorted.remove(at: 0)
            cache[item.key] = nil
            usedCost -= item.cost
        }
    }
    
    public func clear() {
        ArsenalActor.assertIsolated()
        
        cache = [:]
        usedCost = 0
    }
    
    private struct MemoryItem {
        let key: String
        let value: T
        let cost: UInt64
        var timestamp: Date = Date()
        
        init(key: String, value: T) {
            self.key = key
            self.value = value
            self.cost = value.cost
        }
        
        fileprivate init(key: String, value: T, cost: UInt64, timestamp: Date) {
            self.key = key
            self.value = value
            self.cost = cost
            self.timestamp = timestamp
        }
        
        mutating func updateTimestamp() {
            timestamp = Date()
        }
        
        func weakify() -> MemoryWeakItem {
            MemoryWeakItem(key: key, value: value, cost: cost, timestamp: timestamp)
        }
    }
    
    private struct MemoryWeakItem {
        let key: String
        weak var value: T?
        let cost: UInt64
        var timestamp: Date = Date()
        
        init(key: String, value: T, cost: UInt64, timestamp: Date) {
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
    
    private var costLimit: UInt64
    private var cache: [String : MemoryItem] = [:]
    private var usedCost: UInt64 = 0
}

@available(iOS 17.0, macOS 14.0, macCatalyst 17.0, watchOS 10.0, visionOS 1.0, *)
@ArsenalActor fileprivate class DiskArsenal<T: ArsenalItem> : ArsenalImp, @unchecked Sendable {
    
    private let fileManager: FileManager = FileManager()
    private let maxStaleness: TimeInterval
    var costLimit: UInt64
    let identifier: String
    
    init(_ identifier: String, maxStaleness: TimeInterval = 0, costLimit: UInt64 = 0) {
        self.identifier = identifier
        self.maxStaleness = maxStaleness
        self.costLimit = 0
    }
    
    // Base folder for our caches.
    // This can fail, if it does there's not much to do
    // so we just return nil.
    private var cacheURL: URL? {
        if let baseURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first?.appending(component: sanitizedIdentifier) {
            try? fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
            return baseURL
        }
        return nil
    }
    
    lazy private var sanitizedIdentifier: String = sanitize(identifier)
    lazy private var allowedCharacterSet: CharacterSet = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "."))

    // Ensure any key can be used as a name of a fuil on disk.
    private func sanitize(_ key: String) -> String {
        return key.addingPercentEncoding(withAllowedCharacters: allowedCharacterSet) ?? key
    }
    
    // Returns a full valid URL for a key.
    // This is where the cache items appears on disk.
    private func url(for key: String) -> URL? {
        return cacheURL?.appending(component: sanitize(key))
    }
    
    public func update(costLimit to: UInt64) {
        ArsenalActor.assertIsolated()
    }
    
    public func set(_ value: T?, key: String) {
        ArsenalActor.assertIsolated()
        
        guard let url = url(for: key) else {
            return
        }
        if let data = value?.toData() {
            try? data.write(to: url, options: .atomic)
            purge()
        } else {
            try? fileManager.removeItem(at: url)
        }
    }
    
    public func value(for key: String) -> T? {
        ArsenalActor.assertIsolated()
        
        guard let url = url(for: key), let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return nil
        }
        return T.from(data: data) as? T
    }
    
    public func contains(for key: String) -> Bool {
        ArsenalActor.assertIsolated()
        
        if let url = url(for: key) {
            return url.isFileURL ? fileManager.fileExists(atPath: url.path()) : false
        }
        return false
    }
    
    public func purgeUnowned() {}
    
    public func purge() {
        ArsenalActor.assertIsolated()
        
        guard maxStaleness > 0 else {
            return
        }
        
        guard let baseURL = cacheURL else {
            return
        }
        
        // WARNING: By using `.contentModificationDateKey` we need to declare our usage in `PrivacyInfo.xcprivacy`.
        guard let urls = try? fileManager.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles) else {
            return
        }
        
        var sortedUrls = urls.sorted { url1, url2 in
            guard let date1 = try? url1.promisedItemResourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  let date2 = try? url2.promisedItemResourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else {
                return false
            }
            return date1.compare(date2) == .orderedAscending
        }
        
        let now = Date()
        while let url = sortedUrls.first {
            sortedUrls.remove(at: 0)
            
            guard let date = try? url.promisedItemResourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else {
                continue
            }
            
            // Item is too young, since we're sorted we can bail
            guard now.timeIntervalSince1970 - date.timeIntervalSince1970 > maxStaleness else {
                break
            }
            
            // We now know we need to delete the item
            try? fileManager.removeItem(at: url)
        }
        
    }
    
    public func clear() {
        ArsenalActor.assertIsolated()
        
        guard let baseURL = cacheURL else {
            return
        }
        if let urls = try? fileManager.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: nil) {
            for url in urls {
                try? fileManager.removeItem(at: url)
            }
        }
    }
}


