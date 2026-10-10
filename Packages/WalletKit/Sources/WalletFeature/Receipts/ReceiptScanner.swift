import SwiftUI
#if canImport(VisionKit) && os(iOS)
    import VisionKit
#endif

/// Presents the system document scanner and returns the captured pages as JPEG data.
///
/// VisionKit's scanner handles edge detection, perspective correction and multi-page capture, so
/// there is no reason to build a camera UI here. It exists only on iOS; other platforms keep the
/// photo-library path.
#if canImport(VisionKit) && os(iOS)
    struct ReceiptScanner: UIViewControllerRepresentable {
        /// Called with one JPEG per scanned page, in order.
        let onFinish: ([Data]) -> Void
        let onError: (String) -> Void
        @Environment(\.dismiss) private var dismiss

        /// Enough for a legible receipt without storing a full-resolution photo per page.
        static let compressionQuality: CGFloat = 0.7
        static let maximumPageDimension: CGFloat = 2000

        func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
            let controller = VNDocumentCameraViewController()
            controller.delegate = context.coordinator
            return controller
        }

        func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

        func makeCoordinator() -> Coordinator {
            Coordinator(onFinish: onFinish, onError: onError, dismiss: { dismiss() })
        }

        final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
            private let onFinish: ([Data]) -> Void
            private let onError: (String) -> Void
            private let dismiss: () -> Void

            init(onFinish: @escaping ([Data]) -> Void, onError: @escaping (String) -> Void,
                 dismiss: @escaping () -> Void) {
                self.onFinish = onFinish
                self.onError = onError
                self.dismiss = dismiss
            }

            func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                              didFinishWith scan: VNDocumentCameraScan) {
                var pages: [Data] = []
                for index in 0..<scan.pageCount {
                    let image = scan.imageOfPage(at: index)
                    if let data = ReceiptImage.jpeg(from: image) { pages.append(data) }
                }
                dismiss()
                onFinish(pages)
            }

            func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
                dismiss()
            }

            func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                              didFailWithError error: any Error) {
                dismiss()
                onError(error.localizedDescription)
            }
        }
    }

    /// Whether this device can scan at all; simulators and Macs cannot.
    /// Main-actor because VisionKit's check is; every caller is a view.
    @MainActor
    enum ReceiptScannerAvailability {
        static var isSupported: Bool { VNDocumentCameraViewController.isSupported }
    }
#else
    enum ReceiptScannerAvailability {
        static var isSupported: Bool { false }
    }
#endif

enum ReceiptImage {
    #if canImport(UIKit)
        /// Downsamples before encoding so a multi-page scan does not store several megabytes a page.
        static func jpeg(from image: UIImage) -> Data? {
            let longest = max(image.size.width, image.size.height)
            guard longest > 0 else { return nil }
            let scale = min(1, 2000 / longest)
            guard scale < 1 else { return image.jpegData(compressionQuality: 0.7) }
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: size)
            let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            return resized.jpegData(compressionQuality: 0.7)
        }
    #endif
}
