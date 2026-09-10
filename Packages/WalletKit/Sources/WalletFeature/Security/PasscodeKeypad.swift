import SwiftUI
import WalletDomain

/// Filled/empty dots showing how much of the passcode has been entered.
struct PasscodeDots: View {
    let entered: Int
    let length: Int
    var tint: Color = .primary

    var body: some View {
        HStack(spacing: WalletMetrics.large) {
            ForEach(0..<length, id: \.self) { index in
                Circle()
                    .strokeBorder(tint.opacity(0.5), lineWidth: 1.5)
                    .background(Circle().fill(index < entered ? tint : .clear))
                    .frame(width: 14, height: 14)
            }
        }
        .animation(.spring(duration: 0.2), value: entered)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entered) of \(length) digits entered")
    }
}

/// A numeric keypad. Used on the lock screen and when setting a passcode, so it takes no view
/// model and simply reports digits.
struct PasscodeKeypad: View {
    let onDigit: (String) -> Void
    let onDelete: () -> Void
    var biometry: BiometryKind = .none
    var onBiometry: (() -> Void)?
    var isDisabled = false

    private let rows = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]]

    var body: some View {
        VStack(spacing: WalletMetrics.medium) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: WalletMetrics.xxLarge) {
                    ForEach(row, id: \.self) { digit in
                        key(digit) { onDigit(digit) }
                    }
                }
            }
            HStack(spacing: WalletMetrics.xxLarge) {
                if let onBiometry, biometry.isAvailable {
                    control(symbol: biometry.symbol, label: "Unlock with \(biometry.title)", action: onBiometry)
                } else {
                    Color.clear.frame(width: 72, height: 72)
                }
                key("0") { onDigit("0") }
                control(symbol: "delete.left", label: "Delete", action: onDelete)
            }
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
    }

    private func key(_ digit: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(digit)
                .font(.system(size: 30, weight: .regular, design: .rounded))
                .foregroundStyle(.primary)
                .frame(width: 72, height: 72)
                .background(.quaternary.opacity(0.5), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(digit)
    }

    private func control(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.primary)
                .frame(width: 72, height: 72)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
