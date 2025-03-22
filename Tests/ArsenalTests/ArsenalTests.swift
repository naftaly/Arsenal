import XCTest
@testable import Arsenal

@available(iOS 17.0, macOS 14.0, macCatalyst 17.0, watchOS 10.0, visionOS 1.0, *)
class ArsenalTests: XCTestCase {
    var memoryCache: Arsenal<TestItem>!
    var diskCache: Arsenal<TestItem>!
    
    override func setUp() async throws {
        try await super.setUp()
        await memoryCache = Arsenal("testMemory", resources: [.memory: MemoryArsenal<TestItem>(costLimit: 1024 * 500)])
        await diskCache = Arsenal("testDisk", resources: [.disk: DiskArsenal<TestItem>("testDisk", maxStaleness: 2)])
    }
    
    override func tearDown() async throws {
        await memoryCache.clear([.memory, .disk])
        await diskCache.clear([.memory, .disk])
        try await super.tearDown()
    }
    
    func testSetAndGetItem() async {
        let key = "testKey"
        let item = TestItem(data: Data(repeating: 0, count: 1024), cost: 1024)
        
        await memoryCache.set(item, key: key)
        let retrievedItem = await memoryCache.value(for: key)
        
        XCTAssertNotNil(retrievedItem, "Item should be retrievable from memory cache.")
        XCTAssertEqual(retrievedItem?.toData(), item.toData(), "Retrieved item data should match the original.")
        
        await diskCache.set(item, key: key)
        let diskItem = await diskCache.value(for: key)
        
        XCTAssertNotNil(diskItem, "Item should be retrievable from disk cache.")
        XCTAssertEqual(diskItem?.toData(), item.toData(), "Retrieved item data from disk should match the original.")
    }
    
    func testMemoryPurgeOnLimitExceed() async {
        // Setting items until the cache exceeds its limit
        for i in 0..<500 { // Each item is 1024 bytes, limit is 500 MB
            let item = TestItem(data: Data(repeating: UInt8(i % 256), count: 1024), cost: 1024)
            await memoryCache.set(item, key: "key\(i)")
        }
        
        // Trigger a manual purge or wait for the system to purge automatically
        await memoryCache.purge([.memory])
        
        // Assuming the cache uses LRU, the earliest entries should be purged
        let firstItem = await memoryCache.value(for: "key0")
        XCTAssertNil(firstItem, "First item should be purged due to memory limit.")
    }
    
    func testDiskCacheStalenessPurge() async {
        let oldItem = TestItem(data: Data(repeating: 1, count: 1024), cost: 1024)
        await diskCache.set(oldItem, key: "oldKey")
        
        // Simulating passage of time and forcing a purge
        try? await Task.sleep(for: .seconds(3))
        await diskCache.purge([.disk])
        
        let retrievedOldItem = await diskCache.value(for: "oldKey")
        XCTAssertNil(retrievedOldItem, "Old item should be purged based on staleness.")
    }
}

@available(iOS 17.0, macOS 14.0, macCatalyst 17.0, watchOS 10.0, visionOS 1.0, *)
extension ArsenalTests {
    class TestItem: ArsenalItem {
        var data: Data
        var cost: UInt64
        
        init(data: Data, cost: UInt64) {
            self.data = data
            self.cost = cost
        }
        
        func toData() -> Data? {
            return data
        }
        
        static func from(data: Data?) -> ArsenalItem? {
            guard let data = data else { return nil }
            return TestItem(data: data, cost: UInt64(data.count))
        }
    }
}

