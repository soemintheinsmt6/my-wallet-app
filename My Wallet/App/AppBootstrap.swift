import Combine
import Foundation

/// One composition root per app process, shared by all windows.
@MainActor
final class AppBootstrap: ObservableObject {
    @Published private(set) var dependencies: AppDependencies?
    @Published private(set) var errorMessage: String?
    private var isLoading = false

    func load() async {
        guard dependencies == nil, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            // Finish shared initialization even if the initiating window closes.
            dependencies = try await AppDependencies.make()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
