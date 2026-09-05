# Testing

[README](README.md) · [Architecture](ARCHITECTURE.md) · [Design system](DESIGN-SYSTEM.md)

## Commands

Run from the repository root with Xcode selected as the developer toolchain.

```sh
# All Swift Testing suites
swift test --package-path Packages/WalletKit

# Serial run if concurrent Core Data test-store initialization crashes
swift test --package-path Packages/WalletKit --no-parallel

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
| `CategoryTests` | Seed counts/idempotence, edited seed preservation, custom hierarchy, sibling uniqueness, invalid parents/names, replica resolution, published state, failures and account-preserving schema upgrades |
| `CategoryColorTests` | Fixed palette, independence from names/natures and deterministic custom/root-child color mapping |
| `TagTests` | Ten colors, name validation/uniqueness, stable edit identity, selective/idempotent deletion, notifications, view-model failure state and migration/reopening |
| `RecordTests` | Ledger balances, idempotent creation, transfers and received amounts, reference/amount validation, details/photos, label detachment, most-used ranking and additive migration/reopening |

Use in-memory stores for isolated behavior, repository doubles for failures, and unique temporary directories for disk/migration tests. Preserve snapshots of previous schemas when adding upgrade tests. Never point tests at a personal wallet database or live CloudKit container.

Name tests after observable behavior, such as `editsPersistAllSettingsAndPreserveCurrencyAndIdentity`. Add meaningful regression coverage for changed behavior; no numeric coverage threshold is configured.

## Recorded Validation

Amount-grouping validation on 2026-09-05: **43 tests across eight suites passed serially**, and the unsigned iOS Simulator build passed. New tests cover US/German/Indian separators, fractional zeros, incomplete decimals and full supported precision. Manually verify account/payment defaults after saving, cancelling and relaunching; these device preferences are not covered by the formatting tests.

Latest record validation on 2026-09-05: **41 tests across seven suites passed with `--no-parallel`**, and unsigned iOS Simulator/macOS builds passed. Live iCloud record/photo sync, visual/device checks and accessibility remain pending.

On 2026-09-05, after account create/edit settings were implemented:

- All 16 tests passed across three suites.
- Unsigned iOS Simulator and macOS builds passed.
- Local upgrade and disk-reopening checks passed.
- Live iCloud, visionOS, accessibility and visual/device checks were not verified.

No UI automation, snapshot suite or CI workflow is configured. This is a dated result, not a claim that later edits were tested.

Later on 2026-09-05, after category management was implemented, all **24 tests across four suites** passed and unsigned iOS Simulator/macOS builds passed. The additional checks cover 10 roots/50 children, repeat seeding, edits to defaults, two-level hierarchy validation, logical seed-replica resolution and migration preserving existing accounts. Live category sync and visual/accessibility checks remain unverified.

## Manual Account Checklist

Category color validation on 2026-09-05: **28 tests across five suites passed with `--no-parallel`**, and unsigned iOS Simulator/macOS builds passed. The initial parallel run crashed in Core Data's SQL trigger generation during test-store initialization; its root cause remains unconfirmed. The serial run avoids concurrent test-store setup. Color tests verify stable tokens and parent/child mapping, not visual contrast or chart rendering.

Latest validation on 2026-09-05 after category icons/default natures: **26 tests across four suites passed**, including macOS SF Symbol availability for all 60 starter items and migration preserving explicit user natures. Unsigned iOS Simulator and macOS builds also passed. Visual and live iCloud verification remain pending.

1. Create each account type; search/select a currency, enter a balance and choose a color.
2. Reopen the app and confirm saved values. Edit every mutable field; confirm currency remains read-only and Cancel discards edits.
3. Try blank/overlong names, malformed decimals and reversed limits. Confirm failures retain form input.
4. Enable both limits. Check below, exactly at, within and above the range; notices appear only outside enabled limits.
5. Toggle exclusion; confirm the account stays visible and alerts remain active. There is no statistics dashboard to verify yet.
6. Check loading, empty, saving and error states; test larger text, VoiceOver, light/dark appearance and macOS window resizing.
7. Exercise multiple windows and confirm their lists refresh after changes.

## Manual Category Checklist

1. Open Categories and confirm 10 starter roots and 50 total children, including the four Food & Drinks children documented in README.
2. Rename a starter parent and child, set different natures, relaunch and verify both edits and parent links remain intact.
3. Create a custom category and subcategory. Confirm None, Must, Need and Want are available independently at both levels.
4. Try blank/overlong names and duplicate sibling names with different case. Confirm errors retain the draft. Confirm the same child name is accepted under a different parent.
5. Cancel an edit and confirm no change; exercise loading/save failures, keyboard navigation, VoiceOver and larger text.
6. Verify existing account fields after installing the category schema over a previous app build.
7. Verify nature badges show None in gray, Must in green, Need in blue and Want in red, with labels. Rename a category and change its nature; confirm its category color stays fixed and no color editor appears. Confirm children share their parent's category color. Review both light/dark appearances and chart-label contrast when charts are added.

## Manual Label Checklist

1. Create a label using each color; confirm name/color after relaunch. Edit both fields and verify changes.
2. Try blank/overlong names and case/accent variants of existing names. Confirm validation preserves input.
3. Cancel a delete confirmation and verify the label remains. Confirm deletion and verify only the selected label disappears, including after relaunch.
4. Exercise deletion from the editor, swipe actions and context menu; check keyboard/VoiceOver access and larger text.
5. On signed devices, verify label creation, name/color edits and deletion sync through the configured container. Live tag sync is not covered by local tests.

## Manual Record Checklist

For the compact header/footer, verify blank-space taps dismiss each text-field keyboard while taps in fields retain editing. Check the smaller currency capsule and Save button, larger amount and reduced spacing with keyboard open and at accessibility text sizes. Latest compact-layout checks: 43 package tests and unsigned iOS Simulator build passed; device interaction remains unverified.

Verify initial amount focus, hidden currency before account selection, pushed account/payment lists, selected checkmarks, back navigation preserving the draft, currency appearing after selection, and no repeated autofocus when returning. Confirm transfer destinations exclude the source account and category icons match the category list.

Check the reference-inspired record layout on a device: trailing amount/prefix at zero and long values, currency badge, inline title, section icons, required-category indicator and bottom Save button with keyboard visible. Verify larger text and both appearances; compilation alone does not validate these visuals.

1. Create expense/income records with a root category and a subcategory. Check balances, saved date/time and most-used shortcuts separately for each type.
2. Transfer between distinct same-currency accounts, then different currencies with an explicit received amount. Verify both balances; reject zero/negative amounts and identical accounts.
3. Assign multiple labels, rename/recolor one, then delete it. Confirm records and balances remain intact and only its assignment disappears.
4. Save note, payee, payment type and a library photo. Reopen details after relaunch; replace/remove a draft photo and cancel a draft. Check invalid inputs preserve the draft.
5. Edit an account's displayed balance after adding records. Verify the new balance and subsequent record deltas. Future-dated records currently affect balances immediately.
6. Check larger text, VoiceOver, light/dark appearance, keyboard handling and macOS resizing. Test offline saves and cross-device record/photo imports before claiming live sync support.

## iCloud Verification

Provision the configured container and sign two devices into the same iCloud account. Create an account on one device and verify every field on the second after synchronization. Edit balance, limits, color and exclusion; verify imported changes and notices.

Check background/foreground transitions, relaunching, and offline edits followed by reconnection. Refresh reads the local store and does not force synchronization. Validate development schema changes and production deployment separately. Record devices, OS versions, environment, results and unresolved failures.

For categories, seed independently on two offline devices, rename a starter on one, then reconnect. Verify one visible category per seed ID, preserved edits and correct child links. Test custom category creation and nature edits across devices. Local duplicate-replica tests do not establish CloudKit delivery or conflict convergence.

## Completing a Feature

Run checks appropriate to the changed behavior, report actual results and remaining gaps, and update [README.md](README.md) in the same change. Documentation-only changes require content/link checks; app tests need not be rerun unless executable behavior changed.
