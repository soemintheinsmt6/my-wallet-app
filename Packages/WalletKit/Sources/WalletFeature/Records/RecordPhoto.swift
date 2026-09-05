import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import WalletDomain
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum RecordPhoto {
    static func prepare(_ data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 1600,
                kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary) else { throw RecordValidationError.invalidPhoto }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw RecordValidationError.invalidPhoto
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw RecordValidationError.invalidPhoto }
        guard output.length <= 5 * 1024 * 1024 else { throw RecordValidationError.photoTooLarge }
        return output as Data
    }
}

struct RecordPhotoView: View {
    let data: Data
    var body: some View {
        #if os(macOS)
        if let image = NSImage(data: data) {
            Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 240).accessibilityLabel("Attached photo")
        }
        #else
        if let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 240).accessibilityLabel("Attached photo")
        }
        #endif
    }
}
