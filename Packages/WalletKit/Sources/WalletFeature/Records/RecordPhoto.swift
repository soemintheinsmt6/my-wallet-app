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
    /// `nil` lets the image fill whatever space it is given, as the full-screen viewer wants.
    var maxHeight: CGFloat? = 240
    var body: some View {
        #if os(macOS)
        if let image = NSImage(data: data) {
            Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: maxHeight).accessibilityLabel("Attached photo")
        }
        #else
        if let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: maxHeight).accessibilityLabel("Attached photo")
        }
        #endif
    }
}

/// The attached photo at full size, with the only way to remove it.
struct RecordPhotoViewer: View {
    let data: Data
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            // A scroll view proposes no size, so the image would draw at its full pixel width and
            // open zoomed in. A plain bounded frame fits it to the sheet instead.
            RecordPhotoView(data: data, maxHeight: nil)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(WalletMetrics.large)
                .navigationTitle("Photo")
                #if !os(macOS)
                    .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: { Image(systemName: "xmark") }
                            .accessibilityLabel("Close")
                    }
                    ToolbarItem {
                        Button("Delete", role: .destructive) {
                            dismiss()
                            onDelete()
                        }
                        .tint(.red)
                    }
                }
        }
    }
}
