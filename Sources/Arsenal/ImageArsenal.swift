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
            jpegData(compressionQuality: 1)
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

        /// The estimated memory cost of storing this image in bytes.
        ///
        /// Calculated as `width * height * scale^2 * 4` to account for
        /// actual pixel dimensions and 4 bytes per pixel (RGBA).
        public var cost: UInt64 {
            let pixelWidth = size.width * scale
            let pixelHeight = size.height * scale
            return UInt64(pixelWidth * pixelHeight) * 4
        }
    }

#endif
