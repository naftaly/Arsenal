@testable import Arsenal
import XCTest

/// Performance benchmarks for Arsenal caching operations.
///
/// Run with: `swift test --filter Benchmark`
@available(iOS 17.0, macOS 14.0, macCatalyst 17.0, watchOS 10.0, visionOS 1.0, *)
class ArsenalBenchmarks: XCTestCase {
    // MARK: - Memory Cache Benchmarks

    func testBenchmarkMemorySet() async throws {
        let cache = await Arsenal<BenchmarkItem>("benchMemorySet", resources: [
            .memory: MemoryArsenal<BenchmarkItem>(costLimit: 0), // No limit for benchmark
        ])

        let items = (0 ..< 1000).map { i in
            BenchmarkItem(data: Data(repeating: UInt8(i % 256), count: 1024), cost: 1024)
        }

        measure {
            let expectation = self.expectation(description: "Memory set")
            Task {
                for (i, item) in items.enumerated() {
                    await cache.set(item, key: "key\(i)")
                }
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 30)
        }

        await cache.clear([.memory])
    }

    func testBenchmarkMemoryGet() async throws {
        let cache = await Arsenal<BenchmarkItem>("benchMemoryGet", resources: [
            .memory: MemoryArsenal<BenchmarkItem>(costLimit: 0),
        ])

        // Pre-populate cache
        for i in 0 ..< 1000 {
            let item = BenchmarkItem(data: Data(repeating: UInt8(i % 256), count: 1024), cost: 1024)
            await cache.set(item, key: "key\(i)")
        }

        measure {
            let expectation = self.expectation(description: "Memory get")
            Task {
                for i in 0 ..< 1000 {
                    _ = await cache.value(for: "key\(i)")
                }
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 30)
        }

        await cache.clear([.memory])
    }

    func testBenchmarkMemorySetWithPurge() async throws {
        // Cache with limit that will trigger purges
        let cache = await Arsenal<BenchmarkItem>("benchMemoryPurge", resources: [
            .memory: MemoryArsenal<BenchmarkItem>(costLimit: 100 * 1024), // 100 KB limit
        ])

        let items = (0 ..< 500).map { i in
            BenchmarkItem(data: Data(repeating: UInt8(i % 256), count: 1024), cost: 1024)
        }

        measure {
            let expectation = self.expectation(description: "Memory set with purge")
            Task {
                for (i, item) in items.enumerated() {
                    await cache.set(item, key: "purgeKey\(i)")
                }
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 30)
        }

        await cache.clear([.memory])
    }

    // MARK: - Disk Cache Benchmarks

    func testBenchmarkDiskSet() async throws {
        let cache = await Arsenal<BenchmarkItem>("benchDiskSet", resources: [
            .disk: DiskArsenal<BenchmarkItem>("benchDiskSet", maxStaleness: 0, costLimit: 0),
        ])

        // Clear any existing data
        await cache.clear([.disk])

        let items = (0 ..< 100).map { i in
            BenchmarkItem(data: Data(repeating: UInt8(i % 256), count: 1024), cost: 1024)
        }

        measure {
            let expectation = self.expectation(description: "Disk set")
            Task {
                for (i, item) in items.enumerated() {
                    await cache.set(item, key: "diskKey\(i)")
                }
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 60)
        }

        await cache.clear([.disk])
    }

    func testBenchmarkDiskGet() async throws {
        let cache = await Arsenal<BenchmarkItem>("benchDiskGet", resources: [
            .disk: DiskArsenal<BenchmarkItem>("benchDiskGet", maxStaleness: 0, costLimit: 0),
        ])

        // Pre-populate cache
        for i in 0 ..< 100 {
            let item = BenchmarkItem(data: Data(repeating: UInt8(i % 256), count: 1024), cost: 1024)
            await cache.set(item, key: "diskKey\(i)")
        }

        measure {
            let expectation = self.expectation(description: "Disk get")
            Task {
                for i in 0 ..< 100 {
                    _ = await cache.value(for: "diskKey\(i)")
                }
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 60)
        }

        await cache.clear([.disk])
    }

    // MARK: - Combined Cache Benchmarks

    func testBenchmarkCombinedSetBoth() async throws {
        let cache = await Arsenal<BenchmarkItem>(
            "benchCombined",
            costLimit: 0,
            maxStaleness: 86400
        )

        await cache.clear([.memory, .disk])

        let items = (0 ..< 100).map { i in
            BenchmarkItem(data: Data(repeating: UInt8(i % 256), count: 1024), cost: 1024)
        }

        measure {
            let expectation = self.expectation(description: "Combined set")
            Task {
                for (i, item) in items.enumerated() {
                    await cache.set(item, key: "combinedKey\(i)")
                }
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 60)
        }

        await cache.clear([.memory, .disk])
    }

    func testBenchmarkCombinedGetWithPromotion() async throws {
        let cache = await Arsenal<BenchmarkItem>(
            "benchPromotion",
            costLimit: 0,
            maxStaleness: 86400
        )

        // Set items only to disk
        for i in 0 ..< 100 {
            let item = BenchmarkItem(data: Data(repeating: UInt8(i % 256), count: 1024), cost: 1024)
            await cache.set(item, key: "promoKey\(i)", types: [.disk])
        }

        measure {
            let expectation = self.expectation(description: "Get with promotion")
            Task {
                for i in 0 ..< 100 {
                    // This will read from disk and promote to memory
                    _ = await cache.value(for: "promoKey\(i)")
                }
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 60)
        }

        await cache.clear([.memory, .disk])
    }

    // MARK: - Large Item Benchmarks

    func testBenchmarkLargeItemMemory() async throws {
        let cache = await Arsenal<BenchmarkItem>("benchLargeMemory", resources: [
            .memory: MemoryArsenal<BenchmarkItem>(costLimit: 0),
        ])

        // 1 MB items
        let items = (0 ..< 50).map { i in
            BenchmarkItem(data: Data(repeating: UInt8(i % 256), count: 1024 * 1024), cost: UInt64(1024 * 1024))
        }

        measure {
            let expectation = self.expectation(description: "Large item memory")
            Task {
                for (i, item) in items.enumerated() {
                    await cache.set(item, key: "largeKey\(i)")
                }
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 30)
        }

        await cache.clear([.memory])
    }

    func testBenchmarkLargeItemDisk() async throws {
        let cache = await Arsenal<BenchmarkItem>("benchLargeDisk", resources: [
            .disk: DiskArsenal<BenchmarkItem>("benchLargeDisk", maxStaleness: 0, costLimit: 0),
        ])

        await cache.clear([.disk])

        // 1 MB items
        let items = (0 ..< 20).map { i in
            BenchmarkItem(data: Data(repeating: UInt8(i % 256), count: 1024 * 1024), cost: UInt64(1024 * 1024))
        }

        measure {
            let expectation = self.expectation(description: "Large item disk")
            Task {
                for (i, item) in items.enumerated() {
                    await cache.set(item, key: "largeDiskKey\(i)")
                }
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 60)
        }

        await cache.clear([.disk])
    }

    // MARK: - Throughput Benchmarks

    func testBenchmarkMemoryThroughput() async throws {
        let cache = await Arsenal<BenchmarkItem>("benchThroughput", resources: [
            .memory: MemoryArsenal<BenchmarkItem>(costLimit: 0),
        ])

        let item = BenchmarkItem(data: Data(repeating: 0, count: 512), cost: 512)

        measure {
            let expectation = self.expectation(description: "Throughput")
            Task {
                // Mixed read/write workload
                for i in 0 ..< 5000 {
                    if i % 3 == 0 {
                        await cache.set(item, key: "throughput\(i % 100)")
                    } else {
                        _ = await cache.value(for: "throughput\(i % 100)")
                    }
                }
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 30)
        }

        await cache.clear([.memory])
    }

    // MARK: - Clear Benchmarks

    func testBenchmarkClearMemory() async throws {
        let cache = await Arsenal<BenchmarkItem>("benchClearMemory", resources: [
            .memory: MemoryArsenal<BenchmarkItem>(costLimit: 0),
        ])

        measure {
            let expectation = self.expectation(description: "Clear memory")
            Task {
                // Populate
                for i in 0 ..< 1000 {
                    let item = BenchmarkItem(data: Data(repeating: UInt8(i % 256), count: 1024), cost: 1024)
                    await cache.set(item, key: "clearKey\(i)")
                }
                // Clear
                await cache.clear([.memory])
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 30)
        }
    }

    func testBenchmarkClearDisk() async throws {
        let cache = await Arsenal<BenchmarkItem>("benchClearDisk", resources: [
            .disk: DiskArsenal<BenchmarkItem>("benchClearDisk", maxStaleness: 0, costLimit: 0),
        ])

        measure {
            let expectation = self.expectation(description: "Clear disk")
            Task {
                // Populate
                for i in 0 ..< 100 {
                    let item = BenchmarkItem(data: Data(repeating: UInt8(i % 256), count: 1024), cost: 1024)
                    await cache.set(item, key: "clearDiskKey\(i)")
                }
                // Clear
                await cache.clear([.disk])
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 60)
        }
    }
}

// MARK: - Benchmark Item

@available(iOS 17.0, macOS 14.0, macCatalyst 17.0, watchOS 10.0, visionOS 1.0, *)
extension ArsenalBenchmarks {
    final class BenchmarkItem: ArsenalItem {
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
            return BenchmarkItem(data: data, cost: UInt64(data.count))
        }
    }
}
