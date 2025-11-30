# Arsenal

[![License](https://img.shields.io/badge/license-MIT-green.svg)](https://opensource.org/licenses/MIT)
[![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)](https://swift.org/)
[![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20macOS%20%7C%20tvOS%20%7C%20watchOS%20%7C%20visionOS-lightgrey.svg)]()

A multi-layer caching library for Swift with LRU memory eviction, disk persistence, and full Swift 6 concurrency support.

## Features

- **Dual-Layer Caching** - Memory and disk caches work together with automatic promotion
- **LRU Eviction** - Memory cache evicts least-recently-used items when cost limit is exceeded
- **Disk Persistence** - Items survive app restarts with staleness and cost-based eviction
- **Thread Safety** - All operations isolated via `@globalActor` for Swift 6 strict concurrency
- **SwiftUI Integration** - Environment key for shared image caching
- **Flexible Keys** - Use strings or URLs as cache keys

## Requirements

- iOS 17.0+ / macOS 14.0+ / tvOS 17.0+ / watchOS 10.0+ / visionOS 1.0+
- Swift 6.0+

## Installation

Add Arsenal to your project using Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/naftaly/Arsenal.git", from: "1.0.0")
]
```

Or in Xcode: **File > Add Package Dependencies** and enter the repository URL.

## Usage

### Define a Cacheable Type

Conform your type to `ArsenalItem`:

```swift
import Arsenal

struct CachedData: ArsenalItem {
    let data: Data

    // Cost for cache eviction (e.g., byte size)
    var cost: UInt64 { UInt64(data.count) }

    // Serialize for disk storage
    func toData() -> Data? { data }

    // Deserialize from disk
    static func from(data: Data?) -> ArsenalItem? {
        guard let data else { return nil }
        return CachedData(data: data)
    }
}
```

### Create a Cache

```swift
// Combined memory + disk cache
let cache = await Arsenal<CachedData>(
    "com.myapp.cache",
    costLimit: 50 * 1024 * 1024,  // 50 MB memory limit
    maxStaleness: 86400           // 24 hour disk staleness
)

// Memory-only cache
let memoryCache = await Arsenal<CachedData>("memoryOnly", resources: [
    .memory: MemoryArsenal<CachedData>(costLimit: 10 * 1024 * 1024)
])

// Disk-only cache
let diskCache = await Arsenal<CachedData>("diskOnly", resources: [
    .disk: DiskArsenal<CachedData>("diskOnly", maxStaleness: 3600, costLimit: 100 * 1024 * 1024)
])
```

### Store and Retrieve

```swift
// Store an item (writes to both memory and disk)
await cache.set(item, key: "my-key")

// Store with URL key
await cache.set(item, key: URL(string: "https://example.com/data")!)

// Store to specific layer only
await cache.set(item, key: "disk-only", types: [.disk])

// Retrieve (checks memory first, promotes from disk if needed)
if let cached = await cache.value(for: "my-key") {
    // Use cached item
}

// Remove an item
await cache.set(nil, key: "my-key")
```

### Cache Management

```swift
// Update cost limits at runtime
await cache.update(costLimit: 100 * 1024 * 1024, for: [.memory])

// Manually trigger eviction
await cache.purge([.memory, .disk])

// Clear all cached items
await cache.clear([.memory, .disk])

// Check current usage
let memoryCost = await cache.memoryResourceCost
let diskCost = await cache.diskResourceCost
```

### SwiftUI Image Caching

Arsenal includes built-in `UIImage` support:

```swift
struct ContentView: View {
    @Environment(\.imageArsenal) var imageCache

    var body: some View {
        // Use imageCache for caching images
    }
}
```

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                    Arsenal<T>                       │
│              (Cache Orchestrator)                   │
├─────────────────────────────────────────────────────┤
│  ┌─────────────────┐    ┌─────────────────────┐    │
│  │  MemoryArsenal  │    │    DiskArsenal      │    │
│  │  (LRU Cache)    │◄───│  (File Storage)     │    │
│  │                 │    │                     │    │
│  │ • Cost limit    │    │ • Staleness limit   │    │
│  │ • LRU eviction  │    │ • Cost limit        │    │
│  │ • O(1) access   │    │ • File-per-item     │    │
│  └─────────────────┘    └─────────────────────┘    │
└─────────────────────────────────────────────────────┘
                         │
                         ▼
              ┌─────────────────────┐
              │    ArsenalActor     │
              │  (@globalActor)     │
              │                     │
              │ Thread-safe access  │
              └─────────────────────┘
```

- **Read path**: Memory → Disk (with automatic promotion to memory)
- **Write path**: Memory + Disk (configurable per-operation)
- **Eviction**: LRU for memory, staleness + cost for disk

## Contributing

Contributions welcome! Fork the repo, make your changes, and open a pull request.

## License

Arsenal is available under the MIT License. See the LICENSE file for details.
