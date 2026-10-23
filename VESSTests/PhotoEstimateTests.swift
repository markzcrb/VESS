import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import VESS

@MainActor
@Suite("Photo estimate")
struct PhotoEstimateTests {
    /// A JPEG of `width`×`height` with EXIF and GPS, as a camera would write it.
    private func cameraJPEG(width: Int, height: Int) throws -> Data {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 0.8, green: 0.6, blue: 0.4, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        let properties: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 48.14, kCGImagePropertyGPSLongitude: 17.1],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:10:06 18:40:00"],
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    @Test("Downscaled to 1024 px on the long edge, JPEG, with no GPS or EXIF left")
    func downscale() throws {
        let original = try cameraJPEG(width: 4032, height: 3024)
        let prepared = try #require(PhotoPreparation.jpeg(from: original))
        let source = try #require(CGImageSourceCreateWithData(prepared as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier)
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 1024)
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == 768)
        #expect(properties[kCGImagePropertyGPSDictionary] == nil, "No location")
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        #expect(exif?[kCGImagePropertyExifDateTimeOriginal] == nil, "No capture time")
        #expect(prepared.count < original.count)
        #expect(prepared.base64EncodedString().count < 2_000_000, "Within the server's limit")
    }

    @Test("A small photo isn't enlarged; garbage isn't sent")
    func smallAndBad() throws {
        let small = try #require(PhotoPreparation.jpeg(from: try cameraJPEG(width: 600, height: 800)))
        let properties = try #require(CGImageSourceCreateWithData(small as CFData, nil).flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] })
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == 800)
        #expect(PhotoPreparation.jpeg(from: Data("not an image".utf8)) == nil)
    }

    @Test("The response decodes; items keep per-gram values and scale with the amount")
    func decodeAndScale() throws {
        let json = #"{"items":[{"name":"Grilled salmon","amount":150,"unit":"g","kcal":312,"protein_g":34,"carbs_g":0,"fat_g":19,"confidence":"high"},{"name":"Sesame dressing","amount":15,"unit":"g","kcal":68,"protein_g":0.5,"carbs_g":2.1,"fat_g":6.4,"confidence":"low"},{"name":"  ","amount":10,"unit":"ml","kcal":1,"protein_g":0,"carbs_g":0,"fat_g":0,"confidence":"weird"}],"note":"","remaining":9,"estimated":true}"#
        let response = try JSONDecoder().decode(PhotoEstimateResponse.self, from: Data(json.utf8))
        #expect(response.remaining == 9)
        var items = PhotoEstimateRules.items(from: response)
        #expect(items.count == 2, "A nameless item is dropped")
        #expect(items[0].nutrition.calories.isApproximately(312) && !items[0].needsCheck)
        #expect(items[1].needsCheck, "Low confidence asks for a check")
        items[0].amount = PhotoEstimateRules.stepped(items[0].amount, by: 1)
        #expect(items[0].amount == 160 && items[0].nutrition.calories.isApproximately(312.0 / 150 * 160))
        #expect(PhotoEstimateRules.stepped(10, by: -1) == 1, "Never below 1")
        #expect(PhotoEstimateRules.total(items).calories.isApproximately(312.0 / 150 * 160 + 68))
    }

    @Test("An empty result decodes to no items")
    func empty() throws {
        let response = try JSONDecoder().decode(PhotoEstimateResponse.self, from: Data(#"{"items":[],"note":"No food visible.","remaining":8,"estimated":true}"#.utf8))
        #expect(PhotoEstimateRules.items(from: response).isEmpty && response.note == "No food visible.")
    }

    @Test("Save makes ordinary entries marked photoEstimate, in g or ml; blank items are left out")
    func entries() throws {
        let userID = UUID()
        let date = try TestClock.date(2026, 10, 6, 19, 30)
        let items = [
            EstimatedItem(name: "Brown rice", amount: 180, isMilliliters: false,
                          perUnit: NutritionFacts(calories: 1.12, proteinGrams: 0.026, carbohydrateGrams: 0.23, fatGrams: 0.009), confidence: .medium),
            EstimatedItem(name: "Miso soup", amount: 250, isMilliliters: true,
                          perUnit: NutritionFacts(calories: 0.2, proteinGrams: 0.01, carbohydrateGrams: 0.02, fatGrams: 0.005), confidence: .high),
            EstimatedItem(name: "  ", amount: 100, isMilliliters: false,
                          perUnit: NutritionFacts(calories: 1, proteinGrams: 0, carbohydrateGrams: 0, fatGrams: 0), confidence: .high),
        ]
        let entries = PhotoEstimateRules.entries(items, userID: userID, meal: .dinner, at: date)
        #expect(entries.count == 2)
        #expect(entries.allSatisfy { $0.source == .photoEstimate && $0.mealType == .dinner && $0.loggedAt == date && $0.foodID == nil })
        #expect(entries[0].servingUnit == .gram && entries[1].servingUnit == .milliliter)
        #expect(entries[0].nutrition.calories.isApproximately(201.6))
    }

    @Test("The request carries the JPEG as base64, the meal and the language")
    func request() throws {
        let body = try JSONEncoder().encode(FoodPhotoRequest(jpeg: Data([0xFF, 0xD8, 0xFF]), meal: .dinner, locale: "en"))
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(object == ["image_base64": "/9j/", "media_type": "image/jpeg", "meal": "dinner", "locale": "en"])
    }
}
