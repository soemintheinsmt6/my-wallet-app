import SwiftUI

public struct SettingsView: View {
    @ObservedObject private var viewModel: SettingsViewModel
    @AppStorage(WalletPreferenceKeys.appearance) private var appearance = AppAppearance.system.rawValue
    @State private var confirmingReset = false

    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $appearance) {
                        ForEach(AppAppearance.allCases) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                #if DEBUG
                Section {
                    Button("Reset Wallet Data", role: .destructive) { confirmingReset = true }
                        .disabled(viewModel.isResetting)
                    if viewModel.isResetting { ProgressView("Resetting wallet…") }
                } header: {
                    Text("Temporary Development Tools")
                } footer: {
                    Text("Deletes wallet data, including records, photos, accounts, labels and category edits. iCloud deletions may sync to other devices. Starter categories return on reload. Your theme is kept.")
                }
                #endif
                if let error = viewModel.errorMessage {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .confirmationDialog("Reset all wallet data?", isPresented: $confirmingReset, titleVisibility: .visible) {
                Button("Delete Wallet Data", role: .destructive) {
                    Task { await viewModel.resetData() }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This cannot be undone in the app. Records, photos, accounts, labels and category edits will be deleted. Deletions may sync through iCloud to your other devices. Your theme is kept.")
            }
        }
    }
}
