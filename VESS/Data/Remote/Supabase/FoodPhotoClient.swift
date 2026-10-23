import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Gets a photo ready to send once: at most 1024 px on the long edge, JPEG
/// at 0.7, upright, and with no metadata (no location, camera or time).
nonisolated enum PhotoPreparation {
    static let maxPixelSize = 1024
    static let quality = 0.7

    static func jpeg(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        // Only the pixels and the quality: no EXIF, GPS or TIFF dictionaries.
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

/// The food-photo request: the prepared JPEG, the meal and the language.
nonisolated struct FoodPhotoRequest: Encodable, Sendable {
    let imageBase64: String
    let mediaType = "image/jpeg"
    let meal: String
    let locale: String

    enum CodingKeys: String, CodingKey {
        case imageBase64 = "image_base64"
        case mediaType = "media_type"
        case meal, locale
    }

    init(jpeg: Data, meal: MealType, locale: String) {
        imageBase64 = jpeg.base64EncodedString()
        self.meal = meal.rawValue
        self.locale = locale
    }
}
