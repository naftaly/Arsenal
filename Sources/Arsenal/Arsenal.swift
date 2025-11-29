//
//  Arsenal.swift
//
//  Copyright (c) 2024 Alexander Cohen. All rights reserved.
//

import Foundation

// MARK: - ArsenalItem Protocol

/// A protocol that defines the requirements for items that can be stored in an ``Arsenal`` cache.
///
/// Types conforming to `ArsenalItem` must be reference types (`AnyObject`) and thread-safe (`Sendable`).
/// They must provide serialization capabilities and a cost metric for cache management.
///
/// ## Conforming to ArsenalItem
///
/// To make a type cacheable, implement the required methods:
///
/// ```swift
/// final class MyItem: ArsenalItem {
///     let data: Data
///
///     func toData() -> Data? {
///         return data
///     }
///
///     static func from(data: Data?) -> ArsenalItem? {
///         guard let data else { return nil }
///         return MyItem(data: data)
///     }
///
///     var cost: UInt64 {
///         return UInt64(data.count)
///     }
/// }
/// ```
@available(iOS 17.0, macOS 14.0, macCatalyst 17.0, watchOS 10.0, visionOS 1.0, tvOS 13.0, *)
public protocol ArsenalItem: AnyObject, Sendable {
    /// Serializes the item to `Data` for disk storage.
    ///
    /// - Returns: The serialized data representation, or `nil` if serialization fails.
    func toData() -> Data?

    /// Creates an item from serialized data.
    ///
    /// - Parameter data: The serialized data to deserialize.
    /// - Returns: A new item instance, or `nil` if deserialization fails.
    static func from(data: Data?) -> ArsenalItem?

    /// The cost of storing this item, used for cache limit calculations.
    ///
    /// This value is typically the size in bytes, but can be any consistent unit
    /// as long as all items use the same measurement.
    var cost: UInt64 { get }
}

// MARK: - ArsenalActor

/// A global actor that provides thread-safe isolation for Arsenal cache operations.
///
/// All cache operations are isolated to this actor to ensure thread safety.
/// Use the `@ArsenalActor` attribute to mark code that should run on this actor.
///
/// ```swift
/// @ArsenalActor
/// func cacheOperation() async {
///     // This code runs on the ArsenalActor
/// }
/// ```
@available(iOS 17.0, macOS 14.0, macCatalyst 17.0, watchOS 10.0, visionOS 1.0, tvOS 17.0, *)
@globalActor public struct ArsenalActor {
    /// The actor type used for isolation.
    public actor ActorType {}

    /// The shared actor instance.
    public static let shared: ActorType = .init()
}

// MARK: - ArsenalImp Protocol

/// A protocol defining the interface for cache storage implementations.
///
/// Implement this protocol to create custom cache storage backends.
/// Built-in implementations include ``MemoryArsenal`` and ``DiskArsenal``.
@available(iOS 17.0, macOS 14.0, macCatalyst 17.0, watchOS 10.0, visionOS 1.0, tvOS 17.0, *)
@ArsenalActor public protocol ArsenalImp<T>: Sendable {
    /// The type of items this implementation stores.
    associatedtype T

    /// Stores or removes an item in the cache.
    ///
    /// - Parameters:
    ///   - value: The item to store, or `nil` to remove the existing item.
    ///   - key: The unique key to associate with the item.
    func set(_ value: T?, key: String) async

    /// Retrieves an item from the cache.
    ///
    /// - Parameter key: The key associated with the item.
    /// - Returns: The cached item, or `nil` if not found.
    func value(for key: String) async -> T?

    /// Updates the cost limit for this cache.
    ///
    /// - Parameter to: The new cost limit.
    func update(costLimit to: UInt64) async

    /// Purges items from the cache based on the implementation's eviction policy.
    func purge() async

    /// Purges items that are no longer referenced elsewhere in the application.
    func purgeUnowned() async

    /// Removes all items from the cache.
    func clear() async

    /// The maximum cost allowed before eviction occurs.
    var costLimit: UInt64 { get }

    /// The current total cost of all cached items.
    var cost: UInt64 { get }
}

// MARK: - Arsenal

/// A dual-layer caching system with memory and disk storage.
///
/// Arsenal provides a flexible caching solution that combines fast in-memory access
/// with persistent disk storage. It supports automatic eviction based on cost limits
/// and staleness, and is fully thread-safe through actor isolation.
///
/// ## Overview
///
/// Arsenal uses a two-tier caching strategy:
/// - **Memory cache**: Fast access with LRU (Least Recently Used) eviction
/// - **Disk cache**: Persistent storage with time-based staleness eviction
///
/// When retrieving items, Arsenal checks memory first, then falls back to disk.
/// Items retrieved from disk are automatically promoted to memory for faster subsequent access.
///
/// ## Usage
///
/// ```swift
/// // Create a cache for images
/// let imageCache = Arsenal<UIImage>("com.myapp.images")
///
/// // Store an item
/// await imageCache.set(image, key: "hero-image")
///
/// // Retrieve an item
/// if let cached = await imageCache.value(for: "hero-image") {
///     // Use cached image
/// }
/// ```
///
/// ## Topics
///
/// ### Creating a Cache
/// - ``init(_:costLimit:maxStaleness:)``
/// - ``init(_:resources:)``
///
/// ### Storing and Retrieving Items
/// - ``set(_:key:types:)-1lf3h``
/// - ``set(_:key:types:)-20ori``
/// - ``value(for:)-5nexh``
/// - ``value(for:)-2gxqv``
///
/// ### Managing the Cache
/// - ``purge(_:)``
/// - ``purgeUnowned(_:)``
/// - ``clear(_:)``
/// - ``update(costLimit:for:)``
@available(iOS 17.0, macOS 14.0, macCatalyst 17.0, watchOS 10.0, visionOS 1.0, tvOS 17.0, *)
@ArsenalActor @Observable public final class Arsenal<T: ArsenalItem>: Sendable {
    /// The type of cache resource.
    public enum ResourceType: Sendable {
        /// In-memory cache with LRU eviction.
        case memory
        /// Disk-based cache with staleness eviction.
        case disk
    }

    /// The unique identifier for this cache instance.
    ///
    /// This identifier is used for disk storage paths and debugging.
    public let identifier: String

    /// Creates a new cache with default memory and disk storage.
    ///
    /// - Parameters:
    ///   - identifier: A unique identifier for this cache instance.
    ///   - costLimit: The maximum cost for the memory cache. Defaults to 500 MB.
    ///   - maxStaleness: The maximum age for disk-cached items in seconds. Defaults to 1 day.
    public convenience init(_ identifier: String, costLimit: UInt64 = UInt64(5e+8), maxStaleness: TimeInterval = 86400) {
        self.init(
            identifier,
            resources: [
                .memory: MemoryArsenal<T>(
                    costLimit: costLimit
                ),
                .disk: DiskArsenal<T>(
                    identifier,
                    maxStaleness: maxStaleness,
                    costLimit: costLimit
                ),
            ]
        )
    }

    /// Creates a new cache with custom resource implementations.
    ///
    /// Use this initializer to provide custom cache backends or to configure
    /// only specific resource types.
    ///
    /// - Parameters:
    ///   - identifier: A unique identifier for this cache instance.
    ///   - resources: A dictionary mapping resource types to their implementations.
    public init(_ identifier: String, resources: [ResourceType: any ArsenalImp<T>]) {
        self.identifier = identifier
        self.resources = resources
    }

    /// Stores or removes an item in the cache.
    ///
    /// - Parameters:
    ///   - value: The item to store, or `nil` to remove the existing item.
    ///   - key: The unique key to associate with the item.
    ///   - types: The resource types to update. Defaults to both memory and disk.
    public func set(_ value: T?, key: String, types: Set<ResourceType> = [.memory, .disk]) async {
        await forEachResource(of: types) {
            await $0.set(value, key: key)
        }
    }

    /// Stores or removes an item in the cache using a URL as the key.
    ///
    /// - Parameters:
    ///   - value: The item to store, or `nil` to remove the existing item.
    ///   - key: The URL to use as the cache key.
    ///   - types: The resource types to update. Defaults to both memory and disk.
    public func set(_ value: T?, key: URL, types: Set<ResourceType> = [.memory, .disk]) async {
        await set(value, key: key.absoluteString, types: types)
    }

    /// Retrieves an item from the cache.
    ///
    /// This method checks the memory cache first for fast access. If the item
    /// is not in memory but exists on disk, it's loaded and promoted to memory.
    ///
    /// - Parameter key: The key associated with the item.
    /// - Returns: The cached item, or `nil` if not found.
    public func value(for key: String) async -> T? {
        if let val = await memoryResource?.value(for: key) {
            return val
        }
        if let val: T = await diskResource?.value(for: key) {
            await memoryResource?.set(val, key: key)
            return val
        }
        return nil
    }

    /// Retrieves an item from the cache using a URL as the key.
    ///
    /// - Parameter key: The URL used as the cache key.
    /// - Returns: The cached item, or `nil` if not found.
    public func value(for key: URL) async -> T? {
        await value(for: key.absoluteString)
    }

    /// Updates the cost limit for specified resource types.
    ///
    /// Reducing the cost limit may trigger immediate eviction of items
    /// to bring the cache within the new limit.
    ///
    /// - Parameters:
    ///   - costLimit: The new cost limit.
    ///   - types: The resource types to update. Defaults to memory only.
    public func update(costLimit: UInt64, for types: Set<ResourceType> = [.memory]) async {
        await forEachResource(of: types) {
            await $0.update(costLimit: costLimit)
        }
    }

    /// Purges items from the cache based on each resource's eviction policy.
    ///
    /// For memory caches, this evicts items using LRU until under the cost limit.
    /// For disk caches, this removes stale items that exceed the maximum age.
    ///
    /// - Parameter types: The resource types to purge. Defaults to both memory and disk.
    public func purge(_ types: Set<ResourceType> = [.memory, .disk]) async {
        await forEachResource(of: types) {
            await $0.purge()
        }
    }

    /// Purges items that are no longer referenced elsewhere in the application.
    ///
    /// This is useful for memory caches to release items that are only held by the cache.
    ///
    /// - Parameter types: The resource types to purge. Defaults to both memory and disk.
    public func purgeUnowned(_ types: Set<ResourceType> = [.memory, .disk]) async {
        await forEachResource(of: types) {
            await $0.purgeUnowned()
        }
    }

    /// Returns the total cost of all cached items for the specified resource types.
    ///
    /// - Parameter types: The resource types to include. Defaults to both memory and disk.
    /// - Returns: The sum of costs across all specified resources.
    public func cost(_ types: Set<ResourceType> = [.memory, .disk]) async -> UInt64 {
        types.reduce(into: 0) {
            $0 += resources[$1]?.cost ?? 0
        }
    }

    /// Returns the total cost limit for the specified resource types.
    ///
    /// - Parameter types: The resource types to include. Defaults to both memory and disk.
    /// - Returns: The sum of cost limits across all specified resources.
    public func costLimit(_ types: Set<ResourceType> = [.memory, .disk]) async -> UInt64 {
        types.reduce(into: 0) {
            $0 += resources[$1]?.costLimit ?? 0
        }
    }

    /// Removes all items from the specified resource types.
    ///
    /// - Parameter types: The resource types to clear. Defaults to both memory and disk.
    public func clear(_ types: Set<ResourceType> = [.memory, .disk]) async {
        await forEachResource(of: types) {
            await $0.clear()
        }
    }

    private func forEachResource(of types: Set<ResourceType>, action: @Sendable @escaping (any ArsenalImp<T>) async -> Void) async {
        for type in types {
            if let res = resources[type] {
                await action(res)
            }
        }
    }

    private var memoryResource: (any ArsenalImp<T>)? {
        return resources[.memory]
    }

    private var diskResource: (any ArsenalImp<T>)? {
        return resources[.disk]
    }

    private var resources: [ResourceType: any ArsenalImp<T>]
}

// MARK: - Arsenal Convenience Properties

@available(iOS 17.0, macOS 14.0, macCatalyst 17.0, watchOS 10.0, visionOS 1.0, tvOS 17.0, *)
public extension Arsenal {
    /// The current cost of the disk cache.
    var diskResourceCost: UInt64 {
        diskResource?.cost ?? 0
    }

    /// The cost limit of the disk cache.
    var diskResourceCostLimit: UInt64 {
        diskResource?.costLimit ?? 0
    }

    /// The current cost of the memory cache.
    var memoryResourceCost: UInt64 {
        memoryResource?.cost ?? 0
    }

    /// The cost limit of the memory cache.
    var memoryResourceCostLimit: UInt64 {
        memoryResource?.costLimit ?? 0
    }
}
