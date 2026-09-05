# Repository Guidelines

## Project Structure & Module Organization

`My Wallet/` contains the SwiftUI entry point, `App/` dependency wiring and startup handling, `Assets.xcassets`, and platform entitlements. Open `My Wallet.xcodeproj` for app development.

The local Swift package in `Packages/WalletKit/` separates:

- `Sources/WalletDomain/`: entities, repository contracts, and use cases.
- `Sources/WalletData/`: SwiftData models, actor-isolated persistence, and CloudKit configuration.
- `Sources/WalletFeature/`: SwiftUI views and Combine-powered view models.
- `Tests/WalletKitTests/`: package tests.

Keep dependencies pointing toward `WalletDomain`. Views must not access SwiftData directly. Wire concrete implementations in `AppDependencies`; share startup through `AppBootstrap`.

## Build, Test, and Development Commands

Run commands from the repository root:

```sh
swift test --package-path Packages/WalletKit
```

Builds the package and runs its tests.

```sh
xcodebuild -project 'My Wallet.xcodeproj' -scheme 'My Wallet' -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Builds the app without signing. Use `generic/platform=macOS` for the macOS build. To run locally, select the app scheme and a destination in Xcode, then press Run. Manage dependencies through `Packages/WalletKit/Package.swift`.

## Coding Style & Naming Conventions

Use four-space indentation, UpperCamelCase for types, and lowerCamelCase for members. Match filenames to their primary type, such as `WalletViewModel.swift`. No repository formatter or linter is configured; follow surrounding Swift style.

Keep UI state on `@MainActor`, persistence behind `@ModelActor`, and cross-actor values `Sendable`. Use `async throws` for fallible operations and Combine `@Published` for observable view-model state.

## Testing Guidelines

Use Swift Testing (`@Test`, `#expect`) with descriptive behavior names such as `failedWritePreservesDisplayedEntriesAndReportsError`. Use `.inMemory` storage or repository doubles. Cover changed persistence behavior, published state, and failure paths. No numeric coverage threshold is configured. Run package tests and relevant app builds before review.

## Commit & Pull Request Guidelines

Use a single-line, concise, imperative commit message with no body. Do not add agent co-author trailers or attribution. Keep commits focused. PRs should explain the change, affected modules, validation, and configuration or migration impacts. Link relevant issues and include screenshots for UI changes.

## CloudKit Configuration

Keep container identifiers consistent across `AppDependencies.swift` and both entitlement files. Never commit signing credentials. Follow `README.md` for provisioning and signed-device sync checks; local tests do not verify iCloud synchronization. Review schema compatibility and migration before changing persisted models.
