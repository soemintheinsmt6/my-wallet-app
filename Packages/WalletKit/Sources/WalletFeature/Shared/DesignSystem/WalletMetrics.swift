import SwiftUI

/// Shared geometry tokens. Prefer these over literals so unrelated screens line up with each other.
///
/// The values match the sizes record and category rows already used; they are collected here so a
/// change to row rhythm happens in one place instead of in every view.
enum WalletMetrics {
    /// 4-point spacing scale.
    static let hair: CGFloat = 2
    static let tight: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let xLarge: CGFloat = 20
    static let xxLarge: CGFloat = 28

    /// Minimum height for anything tappable.
    static let touchTarget: CGFloat = 44

    /// Leading icon tiles shared by records, categories, accounts and labels.
    enum Tile {
        static let size: CGFloat = 36
        static let symbol: CGFloat = 18
        static let radius: CGFloat = 10

        /// Header and detail-screen variant.
        static let largeSize: CGFloat = 44
        static let largeSymbol: CGFloat = 22
        static let largeRadius: CGFloat = 12
    }

    enum Chart {
        static let compactHeight: CGFloat = 150
        static let height: CGFloat = 200
        static let donutHeight: CGFloat = 190
    }
}

extension Decimal {
    /// The app-wide money format: account currency, up to eight fractional digits.
    func walletFormatted(_ currencyCode: String) -> String {
        formatted(.currency(code: currencyCode).precision(.fractionLength(0...8)))
    }

    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }
}
