//
//  SwiftDataArsenal.swift
//
//  Copyright (c) 2024 Alexander Cohen. All rights reserved.
//

import Foundation

#if SWIFT_DATA_ARSENAL && canImport(SwiftData)
    import SwiftData

    /// A SwiftData-backed cache implementation for persistent storage.
    ///
    /// `SwiftDataArsenal` uses SwiftData and SQLite for persistent caching.
    /// This is an experimental implementation and some features are not yet complete.
    ///
    /// - Warning: This implementation is experimental. Cost tracking and purging
    ///   are not yet implemented.
    ///
    /// ## Features
    ///
    /// - **SQLite Storage**: Uses SwiftData with SQLite backend
    /// - **External Storage**: Large data is stored externally via `@Attribute(.externalStorage)`
    /// - **Thread Safety**: All operations are isolated to ``ArsenalActor``
    ///
    /// ## Enabling
    ///
    /// This class is only available when the `SWIFT_DATA_ARSENAL` compiler flag is defined.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// let cache = SwiftDataArsenal<MyItem>("com.myapp.cache")
    ///
    /// // Store an item
    /// await cache.set(item, key: "my-key")
    ///
    /// // Retrieve an item
    /// if let cached = await cache.value(for: "my-key") {
    ///     // Use cached item
    /// }
    /// ```
    @available(iOS 17.0, macOS 14.0, macCatalyst 17.0, watchOS 10.0, visionOS 1.0, tvOS 17.0, *)
    @ArsenalActor public class SwiftDataArsenal<T: ArsenalItem>: ArsenalImp {
        /// The SwiftData model for storing cached items.
        @Model
        fileprivate class ArsenalItemModel {
            /// The unique key for this cached item.
            @Attribute(.unique) var key: String

            /// The serialized item data, stored externally for large items.
            @Attribute(.externalStorage) var data: Data?

            /// The cost of the cached item.
            var cost: UInt64

            /// When the item was cached.
            var timestamp: Date = Date()

            /// The deserialized item value (computed lazily).
            @Transient lazy var value: T? = T.from(data: data) as? T

            init(key: String, value: T, cost: UInt64) {
                self.key = key
                data = value.toData()
                self.cost = cost
                self.value = value
            }
        }

        private let maxStaleness: TimeInterval
        private let modelContainer: ModelContainer?
        private let modelContext: ModelContext?
        private let urlProvider: ArsenalURLProvider

        /// The maximum total cost allowed before eviction occurs.
        ///
        /// - Note: Cost-based eviction is not yet implemented.
        public var costLimit: UInt64

        /// The unique identifier for this cache instance.
        let identifier: String

        /// Creates a new SwiftData-backed cache.
        ///
        /// - Parameters:
        ///   - identifier: A unique identifier for the cache database.
        ///   - maxStaleness: The maximum age for cached items (not yet implemented).
        ///   - costLimit: The maximum cost before eviction (not yet implemented).
        init(_ identifier: String, maxStaleness: TimeInterval = 0, costLimit _: UInt64 = 0) {
            self.identifier = identifier
            urlProvider = ArsenalURLProvider(identifier, prefix: "sd", fileManager: FileManager())
            self.maxStaleness = maxStaleness
            costLimit = 0

            if let configURL = urlProvider.url(for: identifier)?.appendingPathExtension("sqlite") {
                let config = ModelConfiguration(identifier, url: configURL)
                modelContainer = try? ModelContainer(for: ArsenalItemModel.self, configurations: config)
            } else {
                modelContainer = try? ModelContainer(for: ArsenalItemModel.self)
            }

            if let container = modelContainer {
                modelContext = ModelContext(container)
            } else {
                modelContext = nil
            }
        }

        /// The current total cost of cached items.
        ///
        /// - Note: Cost tracking is not yet implemented. Always returns `0`.
        public var cost: UInt64 {
            0
        }

        /// Updates the cost limit.
        ///
        /// - Parameter to: The new cost limit.
        /// - Note: Cost-based eviction is not yet implemented.
        public func update(costLimit _: UInt64) {
            ArsenalActor.assertIsolated()
            // noop for now
        }

        /// Stores or removes an item in the cache.
        ///
        /// - Parameters:
        ///   - value: The item to store, or `nil` to remove the existing item.
        ///   - key: The unique key to associate with the item.
        public func set(_ value: T?, key: String) {
            ArsenalActor.assertIsolated()

            if let val = value {
                let item = ArsenalItemModel(key: key, value: val, cost: val.cost)
                modelContext?.insert(item)
            } else {
                let fetchDescriptor = FetchDescriptor<ArsenalItemModel>(predicate: #Predicate { item in
                    item.key == key
                })
                do {
                    if let modelContext, let item = try modelContext.fetch(fetchDescriptor).first {
                        modelContext.delete(item)
                    }
                } catch {
                    // TODO: Handle error
                }
            }
        }

        /// Retrieves an item from the cache.
        ///
        /// - Parameter key: The key associated with the item.
        /// - Returns: The cached item, or `nil` if not found.
        public func value(for key: String) -> T? {
            ArsenalActor.assertIsolated()

            let fetchDescriptor = FetchDescriptor<ArsenalItemModel>(predicate: #Predicate { item in
                item.key == key
            })
            return try? modelContext?.fetch(fetchDescriptor).first?.value
        }

        /// Checks if an item exists in the cache.
        ///
        /// - Parameter key: The key to check.
        /// - Returns: `true` if an item exists, `false` otherwise.
        public func contains(_ key: String) -> Bool {
            ArsenalActor.assertIsolated()

            return value(for: key) != nil
        }

        /// No-op. Weak reference purging doesn't apply to SwiftData storage.
        public func purgeUnowned() {}

        /// Purges items based on configured limits.
        ///
        /// - Note: Purging is not yet implemented.
        public func purge() {
            ArsenalActor.assertIsolated()

            // TODO: Implement purge based on staleness and cost
        }

        /// Removes all items from the cache.
        public func clear() {
            ArsenalActor.assertIsolated()
            try? modelContext?.delete(model: ArsenalItemModel.self)
        }
    }

#endif
