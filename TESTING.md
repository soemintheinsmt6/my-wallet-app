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
| `RecordSearchTests` | Field matching (payee, note, amount, category and parent, label), multi-term AND, case/diacritic insensitivity, relevance ranking and tie-breaks, intersecting filter groups, transfer account legs, date/amount bounds, sort determinism and recent-search history |
| `SettingsTests` | Confirmed-reset operation, deletion notifications, starter reseeding, preference retention/clearing, failure state and appearance mapping |

Use in-memory stores for isolated behavior, repository doubles for failures, and unique temporary directories for disk/migration tests. Preserve snapshots of previous schemas when adding upgrade tests. Never point tests at a personal wallet database or live CloudKit container.

Name tests after observable behavior, such as `editsPersistAllSettingsAndPreserveCurrencyAndIdentity`. Add meaningful regression coverage for changed behavior; no numeric coverage threshold is configured.

## Recorded Validation

Search and filtering validation on 2026-09-10: **89 tests across 16 suites passed with `--no-parallel`**, and unsigned iOS Simulator/macOS builds passed. Nine new tests cover text field matching, multi-term AND, case/diacritic insensitivity, relevance ranking, intersecting filter groups, transfer legs, date/amount boundaries, deterministic sorting and recent-search history; the reset test also asserts that search history is cleared. Search is a pure domain calculation with no schema or repository change, so no migration coverage was needed. Live search interaction, suggestion presentation, large-ledger performance, VoiceOver and Dynamic Type remain manual device checks.

Settings validation on 2026-09-05: **47 tests across nine suites passed serially**, with unsigned iOS Simulator/macOS debug and iOS Simulator release builds passing. Settings tests cover all-data reset and notifications, category reseeding, preference retention/clearing, failure state and appearance mapping. Actual reset, visual theme checks and CloudKit deletion propagation were not exercised against personal/live data.

Source refactor validation on 2026-09-05: **43 tests across eight suites passed with `--no-parallel`**, and unsigned iOS Simulator/macOS builds passed. Existing migration, persistence and record tests cover the reorganized sources. Domain/Feature contain no SwiftData or WalletData imports. Public modules and persisted model definitions remain unchanged; visual/device regression checks are still manual.

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
5. Toggle exclusion; confirm the account stays visible and alerts remain active. Confirm excluded accounts are omitted from Statistics.
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

## Manual Settings Checklist

1. Select Light, Dark and System; verify every tab, sheet and popover, then relaunch. System should follow OS appearance changes and other app windows should update.
2. In a debug build using disposable data, cancel reset and confirm nothing changes. Confirm reset and verify accounts, records/photos, labels and custom/edited categories are removed; starter categories return when loaded.
3. Verify theme is retained, last-used entry defaults are cleared, and other windows discard open drafts. Exercise a reset failure and check the error and retry state.
4. Confirm release builds have no reset button. Test iCloud propagation only with disposable wallets on signed devices; do not claim a complete cloud purge or secure photo erasure.

## iCloud Verification

Provision the configured container and sign two devices into the same iCloud account. Create an account on one device and verify every field on the second after synchronization. Edit balance, limits, color and exclusion; verify imported changes and notices.

Check background/foreground transitions, relaunching, and offline edits followed by reconnection. Refresh reads the local store and does not force synchronization. Validate development schema changes and production deployment separately. Record devices, OS versions, environment, results and unresolved failures.

For categories, seed independently on two offline devices, rename a starter on one, then reconnect. Verify one visible category per seed ID, preserved edits and correct child links. Test custom category creation and nature edits across devices. Local duplicate-replica tests do not establish CloudKit delivery or conflict convergence.

## Completing a Feature

Run checks appropriate to the changed behavior, report actual results and remaining gaps, and update [README.md](README.md) in the same change. Documentation-only changes require content/link checks; app tests need not be rerun unless executable behavior changed.

## Phase 1 Core Gaps Validation (2026-09-06)

All **65 tests across 12 suites passed** using `swift test --package-path Packages/WalletKit --no-parallel`. New lifecycle tests cover kind/account changes, same- and cross-currency transfer reversal, photo replacement/removal, failed edits/deletes, observer invalidation, view-model refresh, account cascade/unlink strategies on either transfer side, category reassignment/name collisions, Uncategorized fallbacks and last-category protection. Category migration tests verify the optional deletion timestamp default, persistence after reopening and resistance to older seed replicas. Statistics tests verify currency separation, exclusions, period boundaries, combined filters, child-category inclusion, zero periods and reconstructed history.

Unsigned iOS Simulator and macOS builds both passed for this change. Visual/accessibility checks and CloudKit schema deployment/device sync remain manual; these local tests do not establish cross-device convergence.

### Manual Core Features Checklist

1. Open a saved record and edit every field. Verify its existing photo loads before Save enables; cancel once, then save replacements/removal. Verify list, detail and account balances refresh.
2. Switch expense/income/transfer and swap source/destination accounts, including currencies. Verify sent/received amounts and account balances. Try deleting from detail, swipe and context actions; cancel once before confirming.
3. Delete an account through its swipe/context action. Review record count, transfer count and current balance. Exercise both Keep Records and Delete Records with incoming/outgoing transfers, and verify surviving accounts and photos.
4. Delete a category with children. Exercise reassignment and cascade, duplicate destination names, Uncategorized records and refusal to remove the final category. Relaunch and confirm deleted starters stay deleted.
5. Inspect Statistics for each period, custom range and currency; combine account/category/label filters. Verify exclusions, transfer treatment, donut legends, zero activity, trend granularity, historical balance explanation and top categories.
6. Review iPhone/iPad/macOS layouts, larger text, VoiceOver, light/dark mode and all six tabs (including compact tab overflow). Run signed-device tests for category tombstones, record/photo changes and account deletions after deploying the additive CloudKit schema.

## Phase 2 Validation (2026-09-06)

**80 tests across 15 suites passed** serially. The added tests cover anchored month-end/leap-year/DST recurrence, count/end bounds, idempotent catch-up, deleted-record receipts, pause/resume/cancel, skips, modified/postponed dates, failure rollback, repeated bill payment, mark-paid-only, budget currency/category/account exclusions, positive rollover, custom-period validation, published planning state and notification intent reconciliation. Migration/reopening tests preserve prior accounts, exact decimals, template photos and completion receipts. Reset covers all new models. Statement tests cover transfer legs and interval boundaries.

The native PDF renderer was exercised with a four-page summary containing 70 categories and a long note. PDFKit verified text/pagination and all four Poppler-rendered pages were visually inspected for margins, wrapping and intact final totals. The QA sample contains synthetic data and is not an app fixture or user report.

Final unsigned iOS Simulator and macOS builds both passed after the last code changes. Notification delivery/permission UI, cross-device CloudKit generation, live app interaction and accessibility remain unverified.

Manual checks:

1. Create monthly/weekly/custom and category/global budgets. Exercise rollover, amount boundaries, excluded accounts and 80%/100% notices. Inspect progress in Statistics and category details.
2. Add each recurring frequency; relaunch after due dates, pause/resume/cancel, modify and skip occurrences, and delete a generated record. Confirm it does not reappear. Move one occurrence after a later regular due date and verify the regular record is still generated.
3. Create bills with on-date and advance notices, deny/allow permission, edit/cancel notifications, mark paid both ways, and repeat a stale confirmation. Verify calendar filtering, overdue highlighting and the next recurring due date.
4. Export monthly/yearly/custom summaries and account statements using multiple currencies, long names/notes and large record lists. Share/save the PDF on both platforms.
5. Deploy the additive CloudKit schema in development and test offline simultaneous edits/generation, receipt sync, deletion and reset on signed devices before production use.

## Home Screen Widgets Validation (2026-09-10)

**104 tests across 18 suites passed.** `WalletSnapshotTests` covers snapshot building (per-currency balance grouping, `excludeFromStats` omission, deterministic primary-currency tie-breaking, month totals excluding transfers, newest-first capped recent entries with resolved parent/child titles and category colors, transfer subtitles naming both accounts, budgets ranked by ratio and clamped meters), the store's encode/decode round trip and overwrite path, `nil` for missing and corrupt files, and `WalletDeepLink` round trips including rejection of foreign URLs and the fallback for a malformed `kind`.

Verified by running the app on an iPhone 17 Pro simulator: the `WalletWidgets.appex` is built and embedded in the app's `PlugIns/`, launching the app creates the `group.com.app.My-Wallet` container and writes a well-formed `wallet-snapshot.json`, and the `mywallet://` scheme is registered — iOS offers to open the app for an external deep link.

**Not verified:** widgets rendering on a real home screen in any family, timeline reloads after data changes, and in-app routing after the deep-link confirmation, because simulator UI input could not be driven from this environment. App Group provisioning for signed device builds is also outstanding.

Manual checks:

1. Add each widget in every supported family. Confirm balance currency selection, month figures, recent record tiles/colors, budget meters and quick-add buttons.
2. Change records, accounts and budgets in the app, then confirm widgets update without relaunching.
3. Tap each widget and each quick-add button. Confirm the correct tab opens and that quick-add opens the editor with the kind preselected.
4. Reset wallet data in a debug build and confirm widgets fall back to their empty states.
5. Confirm widgets still render after the app has not run for a day, and on a device where the App Group container is provisioned.

## App Lock Validation (2026-09-10)

**122 tests across 21 suites passed.** `AppLockPolicyTests` covers fresh-launch locking, each grace-period boundary at 59/60 and 299/300 seconds, backwards-clock handling, passcode validation including non-ASCII digits, and the throttle's back-off curve and 15-minute cap. `PasscodeHasherTests` confirms a verifier matches only its own passcode, that each verifier gets a distinct salt, and that the encoded verifier contains no trace of the passcode. `AppLockViewModelTests` drives the state machine against in-memory doubles: locking on start, unlock clearing failures, a throttle that refuses even the correct passcode until served, biometric success/failure/opt-out, backgrounding across the grace period, confirmation mismatch leaving nothing stored, and disabling requiring the current passcode.

Verified by running on an iPhone 17 Pro simulator: the app launches unlocked when no passcode is set, so the gate passes through without regression.

**Not verified:** the lock screen, keypad and Face ID/Touch ID prompts were not exercised, because simulator UI input could not be driven from this environment. Keychain persistence across reinstall, and biometric enrolment and fallback on real hardware, remain outstanding.

Manual checks:

1. Set a 4-digit and a 6-digit passcode; confirm mismatch is rejected and the length picker resets entry.
2. Force-quit and relaunch; confirm the app locks and Face ID/Touch ID is offered before the keypad.
3. Enter a wrong passcode six times; confirm the countdown appears and the correct passcode is refused until it expires.
4. Exercise each auto-lock setting by backgrounding briefly and beyond the interval. Confirm the app-switcher card shows no balances.
5. Deny or unenroll biometrics and confirm the passcode still unlocks; turn the toggle off and confirm no prompt appears.
6. Turn the lock off with the wrong passcode, then the right one. Reinstall and confirm the keychain item did not survive as a stale lock.
