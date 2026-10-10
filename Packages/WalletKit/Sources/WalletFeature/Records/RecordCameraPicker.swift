import SwiftUI
import WalletDomain
#if os(iOS)
    import UIKit
#endif

/// Whether this device can take a photo; simulators, Macs and watches cannot.
/// Main-actor because UIKit's check is; every caller is a view.
@MainActor
enum RecordCameraAvailability {
    static var isAvailable: Bool {
        #if os(iOS)
            return UIImagePickerController.isSourceTypeAvailable(.camera)
        #else
            return false
        #endif
    }
}

#if os(iOS)
    /// Takes a single photo with the system camera and returns it as JPEG data.
    ///
    /// The record editor keeps one photo, so this hands back one image rather than a session the
    /// user can keep adding to.
    struct RecordCameraPicker: UIViewControllerRepresentable {
        let onCapture: (Data) -> Void
        let onError: (String) -> Void
        @Environment(\.dismiss) private var dismiss

        func makeUIViewController(context: Context) -> UIImagePickerController {
            let controller = UIImagePickerController()
            controller.sourceType = .camera
            controller.delegate = context.coordinator
            return controller
        }

        func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

        func makeCoordinator() -> Coordinator {
            Coordinator(onCapture: onCapture, onError: onError, dismiss: { dismiss() })
        }

        final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
            private let onCapture: (Data) -> Void
            private let onError: (String) -> Void
            private let dismiss: () -> Void

            init(onCapture: @escaping (Data) -> Void, onError: @escaping (String) -> Void,
                 dismiss: @escaping () -> Void) {
                self.onCapture = onCapture
                self.onError = onError
                self.dismiss = dismiss
            }

            func imagePickerController(_ picker: UIImagePickerController,
                                       didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
                let image = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage
                dismiss()
                guard let image, let data = ReceiptImage.jpeg(from: image) else {
                    onError(RecordValidationError.invalidPhoto.localizedDescription)
                    return
                }
                onCapture(data)
            }

            func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
                dismiss()
            }
        }
    }
#endif
