# Testing

[README](README.md) · [Architecture](ARCHITECTURE.md) · [Design system](DESIGN-SYSTEM.md)

## Commands

Run from the repository root with Xcode selected as the developer toolchain.

```sh
# All Swift Testing suites
swift test --package-path Packages/WalletKit

# Account behavior and migration suites
swift test --package-path Packages/WalletKit --filter Account

# iOS Simulator compilation, without signing
xcodebuild -project 'My Wallet.xcodeproj' -scheme 'My Wallet' -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build

# macOS compilation, without signing
xcodebuild -project 'My Wallet.xcodeproj' -scheme 'My Wallet' -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO build

# Whitespace errors in tracked changes
git diff --check
```

A build verifies compilation, not successful launch, visual quality or iCloud delivery. Compiler caches and simulator services require appropriate local permissions.

## Automated Coverage

Tests live in `Packages/WalletKit/Tests/WalletKitTests/` and use Swift Testing (`@Test`, `#expect`, `#require`).

| Suite | Coverage |
| --- | --- |
| `WalletKitTests` | Legacy entry persistence/deletion, invalidations, Combine publication and failure handling |
| `AccountTests` | Seven account types, name validation, create/edit persistence, immutable currency/identity, decimal parsing, limits, exclusions, failed writes and reopening storage |
| `AccountMigrationTests` | Previous account schema upgrades with identity preserved and defaults applied |

Use in-memory stores for isolated behavior, repository doubles for failures, and unique temporary directories for disk/migration tests. Preserve snapshots of previous schemas when adding upgrade tests. Never point tests at a personal wallet database or live CloudKit container.

Name tests after observable behavior, such as `editsPersistAllSettingsAndPreserveCurrencyAndIdentity`. Add meaningful regression coverage for changed behavior; no numeric coverage threshold is configured.

## Recorded Validation

On 2026-09-05, after account create/edit settings were implemented:

- All 16 tests passed across three suites.
- Unsigned iOS Simulator and macOS builds passed.
- Local upgrade and disk-reopening checks passed.
- Live iCloud, visionOS, accessibility and visual/device checks were not verified.

No UI automation, snapshot suite or CI workflow is configured. This is a dated result, not a claim that later edits were tested.

## Manual Account Checklist

1. Create each account type; search/select a currency, enter a balance and choose a color.
2. Reopen the app and confirm saved values. Edit every mutable field; confirm currency remains read-only and Cancel discards edits.
3. Try blank/overlong names, malformed decimals and reversed limits. Confirm failures retain form input.
4. Enable both limits. Check below, exactly at, within and above the range; notices appear only outside enabled limits.
5. Toggle exclusion; confirm the account stays visible and alerts remain active. There is no statistics dashboard to verify yet.
6. Check loading, empty, saving and error states; test larger text, VoiceOver, light/dark appearance and macOS window resizing.
7. Exercise multiple windows and confirm their lists refresh after changes.

## iCloud Verification

Provision the configured container and sign two devices into the same iCloud account. Create an account on one device and verify every field on the second after synchronization. Edit balance, limits, color and exclusion; verify imported changes and notices.

Check background/foreground transitions, relaunching, and offline edits followed by reconnection. Refresh reads the local store and does not force synchronization. Validate development schema changes and production deployment separately. Record devices, OS versions, environment, results and unresolved failures.

## Completing a Feature

Run checks appropriate to the changed behavior, report actual results and remaining gaps, and update [README.md](README.md) in the same change. Documentation-only changes require content/link checks; app tests need not be rerun unless executable behavior changed.
