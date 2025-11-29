//
//  ImageArsenal.swift
//
//  Copyright (c) 2024 Alexander Cohen. All rights reserved.
//

import Foundation

#if canImport(SwiftUI) && canImport(UIKit)
    import SwiftUI
    import UIKit

    // MARK: - SwiftUI Environment

    /// An environment key for accessing a shared image cache.
    ///
    /// Use this to inject an ``Arsenal`` instance for `UIImage` caching
    /// into the SwiftUI environment.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// struct ContentView: View {
    ///     @Environment(\.imageArsenal) var imageCache
    ///
    ///     var body: some View {
    ///         // Use imageCache for caching images
    ///     }
    /// }
    /// ```
    @available(iOS 17.0, macOS 14.0, macCatalyst 17.0, watchOS 10.0, visionOS 1.0, tvOS 17.0, *)
    struct ImageArsenalKey: @preconcurrency EnvironmentKey {
        @ArsenalActor static var defaultValue: Arsenal<UIImage> = .init("com.bedroomcode.image.arsenal")
    }

    @available(iOS 17.0, macOS 14.0, macCatalyst 17.0, watchOS 10.0, visionOS 1.0, tvOS 17.0, *)
    public extension EnvironmentValues {
        /// A shared image cache accessible through the SwiftUI environment.
        ///
        /// Access this property using the `@Environment` property wrapper:
        /// ```swift
        /// @Environment(\.imageArsenal) var imageCache
        /// ```
        var imageArsenal: Arsenal<UIImage> { self[ImageArsenalKey.self] }
    }

    // MARK: - UIImage + ArsenalItem

    /// Extends `UIImage` to conform to ``ArsenalItem`` for caching.
    ///
    /// Images are serialized as JPEG data with maximum quality for storage.
    /// The cost is calculated as `width * height`, representing the relative
    /// size of the image in pixels.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// let imageCache = Arsenal<UIImage>("com.myapp.images")
    ///
    /// // Cache an image
    /// await imageCache.set(myImage, key: "profile-photo")
    ///
    /// // Retrieve from cache
    /// if let cached = await imageCache.value(for: "profile-photo") {
    ///     imageView.image = cached
    /// }
    /// ```
    @available(iOS 17.0, macOS 14.0, macCatalyst 17.0, watchOS 10.0, visionOS 1.0, tvOS 17.0, *)
    extension UIImage: ArsenalItem {
        /// Serializes the image as JPEG data with maximum quality.
        ///
        /// - Returns: JPEG data representation of the image, or `nil` if encoding fails.
        public func toData() -> Data? {
            return jpegData(compressionQuality: 1)
        }

        /// Creates a `UIImage` from serialized data.
        ///
        /// - Parameter data: The image data to decode.
        /// - Returns: A `UIImage` instance, or `nil` if the data is invalid.
        public static func from(data: Data?) -> ArsenalItem? {
            guard let data else {
                return nil
            }
            return UIImage(data: data)
        }

        /// The relative cost of storing this image.
        ///
        /// Calculated as `width * height` in points. This provides a consistent
        /// relative measure for comparing image sizes, regardless of scale factor.
        public var cost: UInt64 {
            return UInt64(size.width * size.height)
        }
    }

#endif
