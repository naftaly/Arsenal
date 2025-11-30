import XCTest

@testable import Arsenal

@available(iOS 17.0, macOS 14.0, macCatalyst 17.0, watchOS 10.0, visionOS 1.0, *)
class ArsenalTests: XCTestCase {
    var memoryCache: Arsenal<TestItem>!
    var diskCache: Arsenal<TestItem>!
    var combinedCache: Arsenal<TestItem>!

    override func setUp() async throws {
        try await super.setUp()
        await memoryCache = Arsenal(
            "testMemory", resources: [.memory: MemoryArsenal<TestItem>(costLimit: 1024 * 500)]
        )
        await diskCache = Arsenal(
            "testDisk", resources: [.disk: DiskArsenal<TestItem>("testDisk", maxStaleness: 2)]
        )
        await combinedCache = Arsenal("testCombined", costLimit: 1024 * 100, maxStaleness: 86400)
    }

    override func tearDown() async throws {
        await memoryCache.clear([.memory, .disk])
        await diskCache.clear([.memory, .disk])
        await combinedCache.clear([.memory, .disk])
        try await super.tearDown()
    }

    // MARK: - Basic Operations

    func testSetAndGetItem() async {
        let key = "testKey"
        let item = TestItem(data: Data(repeating: 0, count: 1024), cost: 1024)

        await memoryCache.set(item, key: key)
        let retrievedItem = await memoryCache.value(for: key)

        XCTAssertNotNil(retrievedItem, "Item should be retrievable from memory cache.")
        XCTAssertEqual(
            retrievedItem?.toData(), item.toData(), "Retrieved item data should match the original."
        )

        await diskCache.set(item, key: key)
        let diskItem = await diskCache.value(for: key)

        XCTAssertNotNil(diskItem, "Item should be retrievable from disk cache.")
        XCTAssertEqual(
            diskItem?.toData(), item.toData(), "Retrieved item data from disk should match the original."
        )
    }

    func testRemoveItem() async {
        let key = "removeKey"
        let item = TestItem(data: Data(repeating: 1, count: 512), cost: 512)

        // Add item
        await memoryCache.set(item, key: key)
        let retrieved = await memoryCache.value(for: key)
        XCTAssertNotNil(retrieved, "Item should exist after setting.")

        // Remove item by setting nil
        await memoryCache.set(nil, key: key)
        let removed = await memoryCache.value(for: key)
        XCTAssertNil(removed, "Item should be nil after removal.")
    }

    func testRemoveItemFromDisk() async {
        let key = "diskRemoveKey"
        let item = TestItem(data: Data(repeating: 2, count: 512), cost: 512)

        await diskCache.set(item, key: key)
        let retrieved = await diskCache.value(for: key)
        XCTAssertNotNil(retrieved, "Item should exist on disk after setting.")

        await diskCache.set(nil, key: key)
        let removed = await diskCache.value(for: key)
        XCTAssertNil(removed, "Item should be nil after removal from disk.")
    }

    func testURLBasedKey() async {
        let url = URL(string: "https://example.com/image.png")!
        let item = TestItem(data: Data(repeating: 3, count: 256), cost: 256)

        await memoryCache.set(item, key: url)
        let retrieved = await memoryCache.value(for: url)

        XCTAssertNotNil(retrieved, "Item should be retrievable using URL key.")
        XCTAssertEqual(retrieved?.toData(), item.toData(), "Retrieved item should match original.")
    }

    // MARK: - Memory Cache Tests

    func testMemoryPurgeOnLimitExceed() async {
        // Setting items until the cache exceeds its limit
        // Each item is 1024 bytes, limit is 512000 bytes (1024 * 500)
        // Adding 501 items (513024 bytes) exceeds the limit
        for i in 0 ..< 501 {
            let item = TestItem(data: Data(repeating: UInt8(i % 256), count: 1024), cost: 1024)
            await memoryCache.set(item, key: "key\(i)")
        }

        // Trigger a manual purge or wait for the system to purge automatically
        await memoryCache.purge([.memory])

        // Assuming the cache uses LRU, the earliest entries should be purged
        let firstItem = await memoryCache.value(for: "key0")
        XCTAssertNil(firstItem, "First item should be purged due to memory limit.")
    }

    func testLRUOrdering() async {
        // Create a small cache that can hold 2 items (costLimit 2500, each item 1000)
        let smallCache = await Arsenal<TestItem>(
            "testLRU",
            resources: [
                .memory: MemoryArsenal<TestItem>(costLimit: 2500),
            ]
        )

        // Add 2 items (each 1000 cost, total 2000 = under limit)
        let item0 = TestItem(data: Data(repeating: 0, count: 100), cost: 1000)
        let item1 = TestItem(data: Data(repeating: 1, count: 100), cost: 1000)
        await smallCache.set(item0, key: "item0")
        await smallCache.set(item1, key: "item1")

        // Access item0 to make it recently used
        _ = await smallCache.value(for: "item0")

        // Add a new item, forcing eviction (total would be 3000, limit is 2500)
        let item2 = TestItem(data: Data(repeating: 2, count: 100), cost: 1000)
        await smallCache.set(item2, key: "item2")

        // item1 should be evicted (oldest accessed), item0 should survive (recently accessed)
        let retrieved0 = await smallCache.value(for: "item0")
        let retrieved1 = await smallCache.value(for: "item1")
        let retrieved2 = await smallCache.value(for: "item2")

        XCTAssertNotNil(retrieved0, "Recently accessed item should survive LRU eviction.")
        XCTAssertNil(retrieved1, "Least recently accessed item should be evicted.")
        XCTAssertNotNil(retrieved2, "Newly added item should exist.")

        await smallCache.clear([.memory])
    }

    func testMemoryCostTracking() async {
        let item1 = TestItem(data: Data(repeating: 1, count: 100), cost: 1000)
        let item2 = TestItem(data: Data(repeating: 2, count: 100), cost: 2000)

        await memoryCache.set(item1, key: "cost1")
        let cost1 = await memoryCache.memoryResourceCost
        XCTAssertEqual(cost1, 1000, "Cost should be 1000 after first item.")

        await memoryCache.set(item2, key: "cost2")
        let cost2 = await memoryCache.memoryResourceCost
        XCTAssertEqual(cost2, 3000, "Cost should be 3000 after second item.")

        await memoryCache.set(nil, key: "cost1")
        let cost3 = await memoryCache.memoryResourceCost
        XCTAssertEqual(cost3, 2000, "Cost should be 2000 after removing first item.")
    }

    // MARK: - Disk Cache Tests

    func testDiskCacheStalenessPurge() async {
        let oldItem = TestItem(data: Data(repeating: 1, count: 1024), cost: 1024)
        await diskCache.set(oldItem, key: "oldKey")

        // Simulating passage of time and forcing a purge
        try? await Task.sleep(for: .seconds(3))
        await diskCache.purge([.disk])

        let retrievedOldItem = await diskCache.value(for: "oldKey")
        XCTAssertNil(retrievedOldItem, "Old item should be purged based on staleness.")
    }

    func testDiskCostBasedPurge() async {
        // Create disk cache with cost limit
        let costLimitedDisk = await Arsenal<TestItem>(
            "testDiskCost",
            resources: [
                .disk: DiskArsenal<TestItem>("testDiskCost", maxStaleness: 0, costLimit: 2000),
            ]
        )

        // Add items exceeding cost limit
        for i in 0 ..< 5 {
            let item = TestItem(data: Data(repeating: UInt8(i), count: 1000), cost: 1000)
            await costLimitedDisk.set(item, key: "diskItem\(i)")
        }

        // Purge should remove oldest items
        await costLimitedDisk.purge([.disk])

        // First items should be gone, later items should remain
        let item0 = await costLimitedDisk.value(for: "diskItem0")
        let item4 = await costLimitedDisk.value(for: "diskItem4")

        XCTAssertNil(item0, "Oldest item should be purged due to cost limit.")
        XCTAssertNotNil(item4, "Newest item should survive cost-based purge.")

        await costLimitedDisk.clear([.disk])
    }

    // MARK: - Combined Cache Tests

    func testDiskToMemoryPromotion() async {
        let key = "promotionKey"
        let item = TestItem(data: Data(repeating: 5, count: 512), cost: 512)

        // Set only to disk
        await combinedCache.set(item, key: key, types: [.disk])

        // Verify not in memory
        let memoryCost = await combinedCache.memoryResourceCost
        XCTAssertEqual(memoryCost, 0, "Memory should be empty before promotion.")

        // Retrieve (should promote to memory)
        let retrieved = await combinedCache.value(for: key)
        XCTAssertNotNil(retrieved, "Item should be retrievable from disk.")

        // Verify now in memory
        let memoryCostAfter = await combinedCache.memoryResourceCost
        XCTAssertGreaterThan(memoryCostAfter, 0, "Item should be promoted to memory after retrieval.")
    }

    func testCombinedCacheSetsBoth() async {
        let key = "bothKey"
        let item = TestItem(data: Data(repeating: 6, count: 256), cost: 256)

        await combinedCache.set(item, key: key)

        let memoryCost = await combinedCache.memoryResourceCost
        let diskCost = await combinedCache.diskResourceCost

        XCTAssertGreaterThan(memoryCost, 0, "Item should be in memory.")
        XCTAssertGreaterThan(diskCost, 0, "Item should be on disk.")
    }

    // MARK: - Clear Tests

    func testClearMemory() async {
        let item = TestItem(data: Data(repeating: 7, count: 512), cost: 512)

        await memoryCache.set(item, key: "clearKey1")
        await memoryCache.set(item, key: "clearKey2")

        let costBefore = await memoryCache.memoryResourceCost
        XCTAssertGreaterThan(costBefore, 0, "Cache should have items before clear.")

        await memoryCache.clear([.memory])

        let costAfter = await memoryCache.memoryResourceCost
        XCTAssertEqual(costAfter, 0, "Cache should be empty after clear.")

        let item1 = await memoryCache.value(for: "clearKey1")
        let item2 = await memoryCache.value(for: "clearKey2")
        XCTAssertNil(item1, "Item 1 should be nil after clear.")
        XCTAssertNil(item2, "Item 2 should be nil after clear.")
    }

    func testClearDisk() async {
        let item = TestItem(data: Data(repeating: 8, count: 512), cost: 512)

        await diskCache.set(item, key: "diskClear1")
        await diskCache.set(item, key: "diskClear2")

        await diskCache.clear([.disk])

        let item1 = await diskCache.value(for: "diskClear1")
        let item2 = await diskCache.value(for: "diskClear2")
        XCTAssertNil(item1, "Item 1 should be nil after disk clear.")
        XCTAssertNil(item2, "Item 2 should be nil after disk clear.")
    }

    // MARK: - Cost Limit Update Tests

    func testUpdateCostLimitTriggersPurge() async {
        // Fill cache with items
        for i in 0 ..< 10 {
            let item = TestItem(data: Data(repeating: UInt8(i), count: 100), cost: 1000)
            await memoryCache.set(item, key: "update\(i)")
        }

        let costBefore = await memoryCache.memoryResourceCost
        XCTAssertEqual(costBefore, 10000, "Should have 10 items totaling 10000 cost.")

        // Reduce limit to trigger purge
        await memoryCache.update(costLimit: 5000, for: [.memory])

        let costAfter = await memoryCache.memoryResourceCost
        XCTAssertLessThanOrEqual(costAfter, 5000, "Cost should be at or below new limit after update.")
    }

    // MARK: - Edge Cases

    func testGetNonexistentKey() async {
        let result = await memoryCache.value(for: "nonexistent")
        XCTAssertNil(result, "Getting nonexistent key should return nil.")
    }

    func testOverwriteExistingKey() async {
        let key = "overwriteKey"
        let item1 = TestItem(data: Data(repeating: 1, count: 100), cost: 100)
        let item2 = TestItem(data: Data(repeating: 2, count: 200), cost: 200)

        await memoryCache.set(item1, key: key)
        let cost1 = await memoryCache.memoryResourceCost
        XCTAssertEqual(cost1, 100, "Cost should reflect first item.")

        await memoryCache.set(item2, key: key)
        let cost2 = await memoryCache.memoryResourceCost
        XCTAssertEqual(cost2, 200, "Cost should reflect replaced item, not sum.")

        let retrieved = await memoryCache.value(for: key)
        XCTAssertEqual(retrieved?.toData(), item2.toData(), "Retrieved item should be the replacement.")
    }

    func testOverwriteExistingKeyOnDisk() async {
        let key = "diskOverwriteKey"
        let item1 = TestItem(data: Data(repeating: 1, count: 100), cost: 100)
        let item2 = TestItem(data: Data(repeating: 2, count: 200), cost: 200)

        await diskCache.set(item1, key: key)
        let cost1 = await diskCache.diskResourceCost
        XCTAssertEqual(cost1, 100, "Disk cost should reflect first item.")

        await diskCache.set(item2, key: key)
        let cost2 = await diskCache.diskResourceCost
        XCTAssertEqual(cost2, 200, "Disk cost should reflect replaced item, not sum.")

        let retrieved = await diskCache.value(for: key)
        XCTAssertEqual(retrieved?.toData(), item2.toData(), "Retrieved item should be the replacement.")
    }

    func testOverwriteExistingKeyOnCombinedCache() async {
        let key = "combinedOverwriteKey"
        let item1 = TestItem(data: Data(repeating: 1, count: 100), cost: 100)
        let item2 = TestItem(data: Data(repeating: 2, count: 200), cost: 200)

        await combinedCache.set(item1, key: key)
        let memoryCost1 = await combinedCache.memoryResourceCost
        let diskCost1 = await combinedCache.diskResourceCost
        XCTAssertEqual(memoryCost1, 100, "Memory cost should reflect first item.")
        XCTAssertEqual(diskCost1, 100, "Disk cost should reflect first item.")

        await combinedCache.set(item2, key: key)
        let memoryCost2 = await combinedCache.memoryResourceCost
        let diskCost2 = await combinedCache.diskResourceCost
        XCTAssertEqual(memoryCost2, 200, "Memory cost should reflect replaced item, not sum.")
        XCTAssertEqual(diskCost2, 200, "Disk cost should reflect replaced item, not sum.")

        let retrieved = await combinedCache.value(for: key)
        XCTAssertEqual(retrieved?.toData(), item2.toData(), "Retrieved item should be the replacement.")
    }

    func testMultipleOverwritesOnDisk() async {
        let key = "multiOverwriteKey"

        // Overwrite the same key multiple times
        for i in 1 ... 5 {
            let item = TestItem(data: Data(repeating: UInt8(i), count: 100), cost: 100)
            await diskCache.set(item, key: key)
        }

        let finalCost = await diskCache.diskResourceCost
        XCTAssertEqual(
            finalCost, 100, "Cost should only reflect the single item, not accumulated from overwrites."
        )

        let retrieved = await diskCache.value(for: key)
        XCTAssertEqual(
            retrieved?.toData(), Data(repeating: 5, count: 100),
            "Retrieved item should be the last written value."
        )
    }

    func testEmptyCachePurge() async {
        // Purging empty cache should not crash
        await memoryCache.purge([.memory])
        await diskCache.purge([.disk])

        let memoryCost = await memoryCache.memoryResourceCost
        let diskCost = await diskCache.diskResourceCost
        XCTAssertEqual(memoryCost, 0, "Empty cache should have zero cost.")
        XCTAssertEqual(diskCost, 0, "Empty disk cache should have zero cost.")
    }

    func testPurgeUnownedReleasesUnreferencedItems() async {
        // Keep a strong reference to this item
        let retainedItem = TestItem(data: Data(repeating: 1, count: 100), cost: 1000)
        await memoryCache.set(retainedItem, key: "retained")

        // Add item without keeping a reference (only cache holds it)
        await memoryCache.set(
            TestItem(data: Data(repeating: 2, count: 100), cost: 1000),
            key: "unretained"
        )

        let costBefore = await memoryCache.memoryResourceCost
        XCTAssertEqual(costBefore, 2000, "Should have 2 items before purge.")

        // Purge items not referenced outside the cache
        await memoryCache.purgeUnowned([.memory])

        let costAfter = await memoryCache.memoryResourceCost
        XCTAssertEqual(costAfter, 1000, "Should have 1 item after purging unowned.")

        // Retained item should still exist
        let retrieved = await memoryCache.value(for: "retained")
        XCTAssertNotNil(retrieved, "Retained item should survive purgeUnowned.")
        XCTAssertEqual(retrieved?.toData(), retainedItem.toData(), "Retained item data should match.")

        // Unretained item should be gone
        let unretained = await memoryCache.value(for: "unretained")
        XCTAssertNil(unretained, "Unretained item should be purged.")
    }
}

// MARK: - Test Item

@available(iOS 17.0, macOS 14.0, macCatalyst 17.0, watchOS 10.0, visionOS 1.0, *)
extension ArsenalTests {
    final class TestItem: ArsenalItem {
        let data: Data
        let cost: UInt64

        init(data: Data, cost: UInt64) {
            self.data = data
            self.cost = cost
        }

        func toData() -> Data? {
            data
        }

        static func from(data: Data?) -> ArsenalItem? {
            guard let data else { return nil }
            return TestItem(data: data, cost: UInt64(data.count))
        }
    }
}
