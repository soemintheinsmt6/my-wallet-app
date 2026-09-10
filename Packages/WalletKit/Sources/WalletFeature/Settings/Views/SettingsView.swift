import SwiftUI

public struct SettingsView: View {
    @ObservedObject private var viewModel: SettingsViewModel
    @AppStorage(WalletPreferenceKeys.appearance) private var appearance = AppAppearance.system.rawValue
    @State private var confirmingReset = false

    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    private var version: String {
        let bundle = Bundle.main
        let short = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(short) (\(build))"
    }

    public var body: some View {
        Form {
            Section {
                Picker("Theme", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Appearance")
            } footer: {
                Text("Applies to every tab and sheet. System follows your device setting.")
            }

            Section("About") {
                LabeledContent("Version", value: version)
                LabeledContent("Sync", value: "iCloud")
            }

            #if DEBUG
            Section {
                Button(role: .destructive) { confirmingReset = true } label: {
                    Label("Reset Wallet Data", systemImage: "trash")
                }
                .disabled(viewModel.isResetting)
                if viewModel.isResetting { ProgressView("Resetting wallet…") }
            } header: {
                Text("Temporary Development Tools")
            } footer: {
                Text("Deletes wallet data, including records, photos, accounts, labels and category edits. iCloud deletions may sync to other devices. Starter categories return on reload. Your theme is kept.")
            }
            #endif

            if let error = viewModel.errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
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
