
# Welcome to Arsenal! 🚀

[![License](https://img.shields.io/badge/license-MIT-green.svg)](https://opensource.org/licenses/MIT)
[![Swift](https://img.shields.io/badge/Swift-5.5-orange.svg)](https://swift.org/)
[![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20macOS%20%7C%20tvOS%20%7C%20watchOS%20%7C%20visionOS-lightgrey.svg)]()

Arsenal is your go-to caching solution for Swift applications, offering powerful memory and disk caching with a sprinkle of modern Swift concurrency magic. Designed with iOS, macOS, watchOS, and visionOS in mind, Arsenal ensures your caching is efficient and thread-safe. Whether you're building a dynamic mobile app or a feature-rich macOS application, Arsenal fits right in, keeping your data snappy and your users happy.

## 🌟 Features

- **Dual Caching:** Enjoy the flexibility of both memory and disk caching.
- **Smart Purging:** Automatic LRU (Least Recently Used) purging for memory and time-based purging for disk caches.
- **Concurrency Ready:** Leveraging Swift's latest concurrency features for top-notch performance and safety.
- **SwiftUI Friendly:** Drops seamlessly into SwiftUI projects, making it perfect for modern iOS development.
- **Observable:** Plug into your reactive setups easily, watching for changes as they happen.

## 📋 Requirements

- iOS 17.0+
- macOS 14.0+
- watchOS 10.0+
- visionOS 1.0+
- Swift 5.5+

## 🔧 Installation

To get started with Arsenal, integrate it directly into your project:

1. In Xcode, select **File** > **Swift Packages** > **Add Package Dependency...**
2. Enter the repository URL `https://github.com/naftaly/arsenal.git`.
3. Specify the version or branch you want to use.
4. Follow the prompts to complete the integration.

## 🚀 Usage

### Set Up Your Cache

```swift
import Arsenal

// Use the image cache directly
@Environment(\.imageCache) var imageCache: Arsenal<UIImage>

// Make your own
var cache = Arsenal<SomeTypeThatImplementsArsenalItem>
```

### Managing Cache Entries

```swift
// Add an image to the cache
await imageCache.set(image, key: "uniqueKey")

// Fetch an image from the cache
let cachedImage = await imageCache.value(for: "uniqueKey")
```

### Fine-tuning Your Cache

```swift
// Expand memory limit to 1 GB
await imageCache.update(costLimit: 1_000_000_000, for: [.memory])
```

### Maintenance

```swift
// Trigger a purge
await imageCache.purge()

// Clear all items from both memory and disk
await imageCache.clear()
```

## 👋 Contributing

Got ideas on how to make Arsenal even better? We'd love to hear from you! Feel free to fork the repo, push your changes, and open a pull request. You can also open an issue if you run into bugs or have feature suggestions.

## 📄 License

Arsenal is proudly open-sourced under the MIT License. Dive into the LICENSE file for more details.
