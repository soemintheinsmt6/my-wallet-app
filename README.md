# My Wallet

A SwiftUI wallet app built with modular MVVM and clean architecture, SwiftData storage, Combine, async/await, and a local Swift Package Manager package.

## Feature Status

Update this table whenever a feature is completed.

| Feature | Status | Current behavior |
| --- | --- | --- |
| Modular architecture | Complete | Domain, data and presentation modules with app-owned dependency injection |
| Account creation and editing | Complete | Name, current balance, type, color and saved settings |
| Account types | Complete | Cash, Checking Account, Credit Card, Savings Account, Investments, Loans & Mortgage, Other |
| Currency selection | Complete | Search by name/code during creation; immutable after saving |
| Local persistence | Complete | SwiftData storage, exact decimal strings and tested local schema upgrades |
| Balance notifications | Complete | In-app notices below a minimum or above a maximum; configurable independently |
| Exclude from stats | Setting complete | Persisted toggle and filtered account collection; excluded accounts still show alerts |
| iCloud synchronization | Configured; device verification pending | Private CloudKit container and platform entitlements |
| Statistics dashboard, transactions, account deletion | Not implemented | Future work |

## Getting Started

Use Xcode with the project's 26.5 platform SDKs. The most recent build validation used Xcode 26.6 and Swift 6.3.3. Package tools require Swift 6.0 or newer.

1. Open `My Wallet.xcodeproj`.
2. Select the `My Wallet` scheme and your destination.
3. Configure signing and iCloud as described below, then Run.
4. Choose **Create Account**, fill in the fields, and save. Tap an account to edit it.

The app targets iOS, macOS and visionOS 26.5. Package minimums are iOS 17, macOS 14 and visionOS 1. iOS Simulator and macOS builds have been verified; visionOS has not.

```sh
swift test --package-path Packages/WalletKit
xcodebuild -project 'My Wallet.xcodeproj' -scheme 'My Wallet' -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

## Account Behavior

Names are trimmed and limited to 80 characters. Amounts accept a sign, the local decimal separator, up to 18 integer digits and 8 fractional digits, without grouping separators. New accounts initially select the device currency, falling back to USD.

Balance alerts use strict comparisons: equality with a limit does not trigger an alert. When both alerts are enabled, minimum must be less than maximum. Notices clear when their conditions no longer hold.

Accounts created before currency/settings were introduced migrate to USD, zero balance, blue, alerts off and stats inclusion on. Currency cannot subsequently be edited. The legacy timestamp sample remains in the package/schema but is not the home screen.

## iCloud Setup

In Xcode Signing & Capabilities, select your team and create/select `iCloud.com.app.My-Wallet` with CloudKit and Push Notifications enabled. Keep the identifier aligned in `AppDependencies.swift` and both entitlement files. The project includes the remote-notification background mode.

Verify account creation and edits on two signed devices using the same iCloud account, including backgrounding and relaunching. Deploy the development CloudKit schema to production before distribution. Sync is eventual; successful local saves and refreshes do not confirm server delivery. See [TESTING.md](TESTING.md) for the verification checklist.

## Documentation

- [ARCHITECTURE.md](ARCHITECTURE.md): module boundaries, data flow, concurrency and storage.
- [TESTING.md](TESTING.md): commands, coverage and manual validation.
- [DESIGN-SYSTEM.md](DESIGN-SYSTEM.md): components, visual conventions and interaction states.
- [AGENTS.md](AGENTS.md): contributor guidelines.

## Feature Completion Workflow

For every completed feature, update this README in the same change:

1. Update **Feature Status** with the implemented behavior and any remaining limitations.
2. Update setup or usage instructions affected by the feature.
3. Record relevant validation in [TESTING.md](TESTING.md), distinguishing automated checks from manual/device checks.
4. Update architecture or design documentation when contracts, storage, navigation or visual conventions change.

Do not mark a feature fully verified when provisioning, migration or device checks remain outstanding.
