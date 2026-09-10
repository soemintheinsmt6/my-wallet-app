import SwiftUI
import WalletDomain

/// The Settings controls for app lock: turn it on, change the passcode, choose biometrics and
/// pick how soon backgrounding re-locks the app.
struct AppLockSettingsSection: View {
    @ObservedObject var viewModel: AppLockViewModel
    @State private var sheet: PasscodeSheet?

    private enum PasscodeSheet: String, Identifiable {
        case create, change, disable
        var id: String { rawValue }
    }

    var body: some View {
        Section {
            Toggle("Require Passcode", isOn: Binding(
                get: { viewModel.isEnabled },
                set: { sheet = $0 ? .create : .disable }
            ))

            if viewModel.isEnabled {
                Button {
                    sheet = .change
                } label: {
                    LabeledContent("Passcode", value: "\(viewModel.passcodeLength.rawValue) digits")
                }
                .foregroundStyle(.primary)

                if viewModel.biometry.isAvailable {
                    Toggle(isOn: $viewModel.useBiometrics) {
                        Label("Unlock with \(viewModel.biometry.title)", systemImage: viewModel.biometry.symbol)
                    }
                }

                Picker("Auto-Lock", selection: $viewModel.gracePeriod) {
                    ForEach(AppLockGracePeriod.allCases) { Text($0.title).tag($0) }
                }

                Button("Lock Now") { viewModel.lockNow() }
            }
        } header: {
            Text("Privacy & Security")
        } footer: {
            Text(footer)
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .create: PasscodeEntrySheet(viewModel: viewModel, mode: .create)
            case .change: PasscodeEntrySheet(viewModel: viewModel, mode: .change)
            case .disable: PasscodeEntrySheet(viewModel: viewModel, mode: .disable)
            }
        }
    }

    private var footer: String {
        guard viewModel.isEnabled else {
            return "A passcode hides your balances and records until you unlock the app. It is stored only on this device and never syncs."
        }
        let biometrics = viewModel.biometry.isAvailable && viewModel.useBiometrics
            ? " \(viewModel.biometry.title) unlocks it, with the passcode as a fallback."
            : ""
        return "Auto-Lock decides how soon leaving the app re-locks it.\(biometrics) Repeated wrong entries are delayed."
    }
}

/// Creating, changing or removing the passcode. Each mode is a short sequence of prompts driven by
/// the same keypad.
private struct PasscodeEntrySheet: View {
    @ObservedObject var viewModel: AppLockViewModel
    let mode: Mode
    @Environment(\.dismiss) private var dismiss

    enum Mode { case create, change, disable }

    /// `current` is only used by change/disable; create starts straight at `enter`.
    private enum Step { case current, enter, confirm }

    @State private var step: Step
    @State private var length = PasscodeLength.six
    @State private var entry = ""
    @State private var firstEntry = ""
    @State private var errorMessage: String?

    init(viewModel: AppLockViewModel, mode: Mode) {
        self.viewModel = viewModel
        self.mode = mode
        _step = State(initialValue: mode == .create ? .enter : .current)
        _length = State(initialValue: viewModel.passcodeLength)
    }

    private var title: String {
        switch mode {
        case .create: "Set Passcode"
        case .change: "Change Passcode"
        case .disable: "Turn Off Passcode"
        }
    }

    private var prompt: String {
        switch step {
        case .current: "Enter your current passcode"
        case .enter: mode == .change ? "Enter your new passcode" : "Enter a passcode"
        case .confirm: "Re-enter your passcode"
        }
    }

    /// While confirming, the length is fixed by the first entry.
    private var activeLength: Int {
        step == .current ? viewModel.passcodeLength.rawValue : length.rawValue
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: WalletMetrics.xLarge) {
                Spacer(minLength: 0)

                Text(prompt)
                    .font(.headline)
                    .multilineTextAlignment(.center)

                PasscodeDots(entered: entry.count, length: activeLength)

                if step == .enter, mode != .disable {
                    Picker("Length", selection: $length) {
                        ForEach(PasscodeLength.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)
                    .onChange(of: length) { _, _ in entry = "" }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Spacer(minLength: 0)
                PasscodeKeypad(onDigit: append, onDelete: { if !entry.isEmpty { entry.removeLast() } })
                Spacer(minLength: 0)
            }
            .padding(WalletMetrics.xLarge)
            .navigationTitle(title)
            #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func append(_ digit: String) {
        guard entry.count < activeLength else { return }
        entry.append(digit)
        errorMessage = nil
        guard entry.count == activeLength else { return }
        advance()
    }

    private func advance() {
        let value = entry
        entry = ""
        switch step {
        case .current:
            guard viewModel.verify(currentPasscode: value) else {
                errorMessage = PasscodeError.incorrect.errorDescription
                return
            }
            if mode == .disable {
                do { try viewModel.disableLock(currentPasscode: value); dismiss() }
                catch { errorMessage = error.localizedDescription }
            } else {
                step = .enter
            }
        case .enter:
            firstEntry = value
            step = .confirm
        case .confirm:
            do {
                try viewModel.setPasscode(firstEntry, confirmation: value, length: length)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                firstEntry = ""
                step = .enter
            }
        }
    }
}
