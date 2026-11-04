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

# Watch app and complications, which the My Wallet scheme does not build
xcodebuild -project 'My Wallet.xcodeproj' -scheme WalletWatch -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project 'My Wallet.xcodeproj' -scheme WalletWatchWidgets -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build

# Lint with the project's .swiftlint.yml (brew install swiftlint)
swiftlint lint

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
| `BalanceAdjustmentTests` | Adjustment increases/decreases changing balances without a category, account balance edits recorded as adjustments without shifting earlier history (and none for a name-only edit), edit/delete reversal, transfers rejected as adjustments, totals excluding adjustments while balance history and statements include them, older drafts decoding and CSV round-tripping |
| `BankStatementImportTests` | Bank header aliases (the app's own names winning), signed amounts, Debit/Credit columns (including negative debits), bank Type values, sign reversal, day-first date detection, bank date forms, accounting negatives, a chosen account filling missing or empty Account cells, typed rows keeping their strict checks, exports unchanged; date-only rows matched one-for-one against existing records; per-kind category fallbacks; and the view model's account choice, sign flip, fallback categories and re-import detection. `ManualEntryMatchingTests` covers matching records entered by hand by day within the posting lag, transfers on both accounts, same-day-first assignment, near amounts within 5% after exact ones, tips up to 25% last, amount updates (including cross-currency transfer sides) and Import Anyway. `TipImportViewModelTests` covers applying updates with the photo kept, the toggle and split records |
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

### Biometrics Without a Passcode (2026-09-11)

**271 tests across 44 suites passed.** `AppLockViewModelTests` gained the biometric-only lock: enabling it with no passcode stored, its prompt accepting the device passcode while a passcode-backed prompt does not, a device that can verify nobody refusing the lock outright, an unverified attempt changing nothing in either direction, and a wallet passcode superseding it without reverting when removed. A regression test pins the fix for the re-lock loop: a successful biometric unlock followed by the return to active the system prompt causes must leave the app unlocked.

**Not verified:** the same limits stand — no simulator UI input, so the prompts themselves were not exercised. The Simulator also reports no biometry unless Features → Face ID → Enrolled is set, which hides the toggle entirely.

Manual checks:

1. With no passcode set, turn on Lock with Face ID. Confirm the prompt appears, the toggle stays on only after it succeeds, and cancelling leaves it off.
2. Relaunch. Confirm the lock screen shows a single unlock button and no keypad, and that Face ID unlocks it and the lock screen does not come back.
3. Cancel the prompt, then unlock with the button. Confirm the device passcode is offered as the fallback.
4. Unenroll Face ID while the lock is on. Confirm the device passcode still unlocks and the button names it.
5. Set a wallet passcode while the biometric lock is on. Confirm the keypad returns and the Lock with Face ID toggle is replaced by Unlock with Face ID.
6. Turn the lock off. Confirm it requires verifying, and that a cancelled prompt leaves the lock standing.

## Export and Import Validation (2026-09-10)

**144 tests across 25 suites passed.** `CSVTests` covers quoting only where required, round-tripping values with embedded commas, quotes and newlines, CRLF/LF/BOM/trailing-newline handling, preserved empty trailing fields, unterminated quotes and empty files. `RecordCSVTests` round-trips a real export back into rows, checks header matching across case, order and unknown columns, missing required columns, spreadsheet-accurate row numbers in errors, both decimal separators with grouping and currency symbols, common date forms, exact decimal output, and case-insensitive payment types. `WalletArchiveTests` covers the JSON round trip, photo bytes being dropped and a newer format being refused. `ImportPlannerTests` covers name matching for accounts/categories/labels, flagged unknown accounts and malformed transfers, duplicates against the wallet and within one file, near-misses that are not duplicates, and the invariant that every row lands in exactly one bucket.

Two defects were found by these tests and fixed: CRLF files failed to parse because Swift treats `\r\n` as one grapheme cluster, and `PaymentType` was lost on import because its camelCase raw values were compared after lowercasing.

**Not verified:** the share sheet, the document picker and the import preview were not exercised on a device or simulator, so file handoff, security-scoped access to a file outside the sandbox, and Excel's handling of the exported CSV remain outstanding.

Manual checks:

1. Export CSV and JSON, share both, and reopen the CSV in Numbers and Excel. Confirm accented names, embedded commas, quotes and multi-line notes survive.
2. Re-import the exported CSV and confirm every row is reported as already in your wallet and nothing is written.
3. Import a file from another app with reordered, renamed and missing optional columns; confirm the preview counts and the errors' row numbers.
4. Import a file naming unknown accounts and new labels. Confirm the labels are created and the unmatched rows are listed rather than silently skipped.
5. Import a large file and confirm progress is reported and a rejected row does not discard the rows already saved.

## Onboarding Validation (2026-09-10)

**152 tests across 26 suites passed.** `OnboardingTests` covers the completion flag being false until finish, skip recording completion, account-step validation for blank names and unparseable balances, the account actually being created with its name/type/currency/balance, a rejected save keeping the step and draft without completing, the optional budget's validation including a refused zero limit, Back never returning to the already-created account, and reaching the end completing onboarding.

Verified on an iPhone 17 Pro simulator: a fresh install shows the welcome step in place of the tabs, with the progress indicator, Skip and the value-proposition rows rendering correctly.

**Known intermittent:** one full test run aborted with `NSUnknownKeyException … entity CategoryRecord is not key value coding-compliant for the key "deletionDate"`. It did not reproduce in eleven subsequent runs, with or without the onboarding changes. This is the same parallel test-store initialization race already recorded above for 2026-09-05 and mitigated by the documented `--no-parallel` command; each added suite that builds an in-memory container increases exposure to it. Still worth pinning down before relying on the parallel suite in CI.

**Not verified:** stepping through account creation, the categories overview, the budget step and Skip on a device or simulator, because simulator UI input could not be driven from this environment.

Manual checks:

1. Install fresh and step through every screen; confirm the account is created with the chosen currency and balance.
2. Use Skip on each step; confirm onboarding does not return on relaunch and any created account is kept.
3. Enter an invalid balance and an empty name; confirm the primary button stays disabled.
4. Turn on the budget step and confirm the budget appears under Planning with the account's currency.
5. Relaunch after finishing and confirm the tabs appear immediately.

## Multi-Currency Validation (2026-09-10)

**167 tests across 29 suites passed.** `CurrencyConverterTests` covers identity conversion, direct rates against the base, cross-rates through the base for a pair neither of which is the base, a missing currency raising rather than guessing, rounding to the target currency's precision including zero-decimal JPY, explicit rates rejecting zero, and the refresh policy including a backwards clock. `CurrencyViewModelTests` covers conversion staying unavailable until the user opts in and rates exist, a failed refresh keeping cached rates and explaining itself, per-amount conversion returning `nil` for an unknown currency, a pinned rate overriding the market rate and working with no rates at all, combined totals refusing to guess when one currency is missing, and transfer gain/loss including the same-currency case. `ManualRateValidationTests` covers rejecting non-positive pinned rates and a round trip of the new persisted field, including records saved without one.

All existing migration suites still pass with the added `manualRateValue` field.

**Not verified:** no request was made against the live Frankfurter endpoint from this environment, so the real response shape, historical-day queries and failure handling on a metered or offline connection are untested. The added persisted field has not been checked against a deployed CloudKit schema.

Manual checks:

1. Set a home currency, turn on converted totals, and confirm the Home balance shows a combined `≈` figure only when more than one currency is present.
2. Turn converted totals off and confirm every screen returns to per-currency figures with no estimates anywhere.
3. Go offline and relaunch; confirm cached rates still convert and the settings screen says which day they are from.
4. Pin a rate on a record in a non-home currency and confirm the detail screen shows the pinned rate and uses it; clear the field and confirm it reverts to the market rate.
5. Make a cross-currency transfer and confirm the gain or loss reads in the home currency and flips sign correctly.
6. Deploy the schema change to the CloudKit development environment and confirm records sync both ways between a device with the field and one without.

## Siri and Shortcuts Validation (2026-09-10)

**No automated tests.** The intents live in the app target, which has no test target, so they are not covered by the package suite. Verified instead by inspecting the built app's `Metadata.appintents/extract.actionsdata`: it contains three actions (`AddExpenseIntent`, `ShowBalanceIntent`, `MonthlySummaryIntent`), the `WalletShortcuts` provider, and every Siri phrase template. Before these were added the build logged "Metadata extraction skipped. No AppIntents.framework dependency found"; it now runs `ExtractAppIntentsMetadata`.

**Not verified:** no intent was invoked from Siri, the Shortcuts app or a widget, and no Spotlight result was opened. Adding an expense by voice writes real data, so exercise it on a test wallet first.

Manual checks:

1. Run each action from the Shortcuts app. Confirm the account and category pickers list real entries and that categories show their full path.
2. Say each Siri phrase. Confirm Add Expense asks which account when several exist and uses the only one when there is just one.
3. Add an expense by voice and confirm the record, its amount rounding and the account balance in the app.
4. Search an account and a category name in Spotlight; confirm no balance appears in the result and that opening one lands on More.
5. Rename an account, then search the old and new names. Delete one and confirm it leaves the index.
6. Reset wallet data in a debug build and confirm Spotlight results disappear.

## Apple Watch Validation (2026-09-11)

**172 tests across 29 suites passed** (serially; the parallel run hit the known store race again). New coverage is for the shared pieces the watch relies on, all of which live in the package: quick-add options covering accounts and most-used expense categories while omitting accounts excluded from stats, today's spend counting only today's expenses in the leading currency, the WatchConnectivity payload codec round-tripping in both directions and rejecting foreign payloads, and a snapshot written before the quick-add fields still decoding.

**Not compiled.** The watchOS 26.5 platform is not installed in this environment — only its SDK headers — so `WalletWatch` and `WalletWatchWidgets` could not be built, and no watch code has been through a compiler. `xcodebuild -downloadPlatform watchOS` was started and was still at 3.4% of 3.96 GB when work moved on.

To keep the iOS build working meanwhile, the iOS target's Embed Watch Content phase and its dependency on `WalletWatch` are detached; see FEATURES.md 4.2 for the two steps to restore them.

Manual checks (all outstanding):

1. Install the watchOS platform, then build both watch targets and fix whatever the compiler finds.
2. Re-attach Embed Watch Content and confirm the watch app installs alongside the iOS app.
3. Open the watch app with the phone nearby; confirm balance, today's spending and the month figures match.
4. Add an expense from the watch and confirm the record appears on the phone with the right account, category and amount.
5. Put the phone in airplane mode, capture an expense, and confirm it is queued and delivered once reachable.
6. Add both complications to a face and confirm they update after a change on the phone.

## iPad and Adaptive Layout Validation (2026-09-11)

**177 tests across 31 suites passed** serially. New coverage is for the parts that are testable without a window: `WalletCommandBus` publishing each new-record request as a counter rather than a flag (so a second ⌘N still opens the editor), search and tab requests, the tab count matching the ⌘1–⌘5 shortcut slots, and `RecordTransfer` carrying only the record identifier under the app's own exported UTI rather than plain text.

Verified on an iPad Pro 13-inch simulator: the regular-width layout renders the sidebar with all five destinations and shows Home beside Statistics in the detail column, with the statistics period control and stepper working in the narrower column.

**Not verified:** keyboard shortcuts (no hardware keyboard could be driven), drag-and-drop of a record onto a category, multi-window, and the compact/regular transition on rotation.

Manual checks:

1. Rotate an iPad between orientations and split-screen widths; confirm the layout switches between tabs and sidebar without losing the selected destination.
2. With a keyboard attached, try ⌘N, ⇧⌘N, ⇧⌘T, ⌘F and ⌘1–⌘5; confirm each acts on the frontmost window.
3. Drag a record onto a category in the sidebar's Categories screen; confirm it is refiled and the balance is unchanged. Try dragging a transfer without a category and confirm it is ignored.
4. Open a second window from the app's Dock menu; confirm each window navigates independently and both refresh after an edit.
5. Confirm dragging a record into another app does nothing (the type is app-private).

## Insights and Notifications Validation (2026-09-11)

**190 tests across 33 suites passed** serially. `InsightsTests` covers week and month comparisons against the preceding period, a withheld percentage when there is no prior spending, transfers/income/excluded accounts never counting as spending, a category flagged only against its own three-month average, steady spending and sub-minimum amounts not being flagged, logging streaks counting back from today, a streak ending yesterday still counting, gaps breaking a streak, several records in one day counting once, and an empty wallet producing nothing. `InsightPreferencesTests` covers every notice defaulting to off and the planning and insight identifier prefixes being disjoint.

**Defect found and fixed:** `synchronize` previously cancelled every pending `wallet.`-prefixed notice not in the batch, so adding a second source of notifications would have silently cancelled all bill and budget alerts. Callers now declare the prefixes they own.

**Not verified:** no notification was scheduled or delivered — authorization, trigger dates, the weekly/monthly schedule and the once-per-month anomaly key all need a device.

Manual checks:

1. Turn on each notice, grant permission, and confirm the weekly summary arrives on the chosen weekday and hour.
2. Create budgets and bills, then turn insight notices on and off repeatedly; confirm bill and budget alerts are still delivered.
3. Overspend a category against its history and confirm exactly one unusual-spending alert that month.
4. Turn a notice off and confirm its pending notification is cancelled.
5. Log records on consecutive days and confirm the streak on Home; skip a day and confirm it resets.

## Receipt Capture Validation (2026-09-11)

**205 tests across 35 suites passed** serially. `ReceiptTextReaderTests` covers a line naming the total winning over larger numbers, subtotals/tax/change being excluded, the largest amount as fallback, grouped and comma-decimal forms, text with no amount, integers not being mistaken for money, common date formats, and future dates rejected. `ReceiptStorageTests` covers pages stored in order and appended after existing ones, per-record page counts, oversized and empty pages rejecting the whole batch, the 12-page limit, deleting one page leaving the rest, **deleting a record removing its pages**, and **Reset Wallet Data clearing every page** — the last two matter because orphaned image blobs would be invisible and permanent.

**Bug found and fixed:** the amount pattern accepted only a space or comma as a group separator, so `1.234,56` parsed as `234.56`.

**Not verified:** no scan was performed. The camera, VisionKit's scanner, image downsampling, real Vision OCR output and the camera permission prompt all need a physical device — `VNDocumentCameraViewController.isSupported` is false on the simulator, so the scan button does not even appear there.

Manual checks:

1. Scan a single-page and a multi-page receipt; confirm pages keep their order and open full screen.
2. Confirm the OCR suggestion appears, that accepting it fills the amount and date, and that dismissing it changes nothing.
3. Scan a receipt with a subtotal larger than the total and confirm the total is chosen.
4. Delete a page, then delete the record; confirm no pages survive and storage does not grow.
5. Deny camera permission and confirm the failure is reported rather than the app hanging.
6. Confirm receipt pages are excluded from PDF and CSV/JSON exports.

## Phase 5 Validation (2026-09-11)

**260 tests across 44 suites passed** serially.

`DebtCalculationTests` and `GoalCalculationTests` cover outstanding balances falling as payments land, a fully paid debt never going negative, per-person netting that keeps currencies apart and matches names case-insensitively, settled debts sinking below outstanding ones, overdue applying only while outstanding, goal progress with withdrawals, rate-based projection, projection withheld without contributions or once achieved, behind-schedule against a deadline, and an achieved goal never being behind. `DebtGoalStorageTests` covers round trips, a payment beyond the outstanding balance being refused, and deleting a debt or goal removing its payments or contributions.

`SplitCalculatorTests` covers equal shares always summing back to the exact total (10 three ways is 3.34/3.33/3.33), zero-decimal currencies, percentage conversion with drift absorbed, validation that shares *and* payments must cover the record, and settlement suggestions — that applying every suggestion leaves all balances at zero, that a mixed group needs few payments, and that the plan is deterministic. `SplitBudgetTests` asserts a 90 bill fronted for three charges only 30 to the payer's budget.

`DashboardConfigurationTests` covers defaults, a card added later being appended rather than resetting the arrangement, toggling keeping position, reordering, period windows, and persistence across a relaunch. `ThemeTests` covers the Default accent applying no tint, Standard text size not overriding Dynamic Type, persistence, and a failed icon change being reported without changing the icon. `CategorySymbolStoreTests` covers the seeded symbol as fallback and clearing restoring it.

**Not verified:** no Phase 5 screen was exercised on a device. Debt reminders were not delivered, drag reordering of dashboard cards was not performed, alternate app icons were not applied (`setAlternateIconName` needs a device), and the goal celebration was not seen. `CKShare` sharing is not implemented at all.

Manual checks:

1. Create debts in both directions for one person; confirm they net into a single balance and that partial payments reduce it.
2. Settle a debt with and without creating a record; confirm balances change only in the first case.
3. Split a bill three ways and confirm the shares add to the exact total, including an amount that does not divide evenly.
4. Confirm the settlement suggestions clear every balance when followed, and that your own budget is charged only your share.
5. Reorder and hide dashboard cards; relaunch and confirm the arrangement survives.
6. Change accent, density and text size; confirm text size stacks with the system Dynamic Type setting rather than replacing it.
7. Switch app icons on a device and confirm the Home Screen updates and the choice persists.
8. Reach a savings goal and confirm the celebration plays once, and holds still under Reduce Motion.

## Interface Polish and Dashboard Validation (2026-11-01)

**299 tests across 49 suites passed.** One run hit an intermittent failure in `screensSharingTheRecordsModelLoadItOnceBetweenThem`, which depends on timing (racing tasks and a 50 ms sleep); it passed in isolation and in three further full runs, and the session's changes do not touch record loading.

New and updated coverage: `AccountTests` covers a chosen account icon persisting, changing and clearing back to the type's icon; `WalletArchiveTests` covers icons in the backup and older backups without the key still decoding; `AccountSymbolTests` covers the type fallback. `DashboardConfigurationTests` covers `ActivityPeriod` windows (day, week, month and a leap year), older arrangements decoding with their period and account scope ignored, and the Accounts and chart cards being introduced after Balance and the summary rather than appended. `AccountActivityTests` covers totals counting only the account's own income and expenses while transfers in either direction are listed, newest first. `ExpenseBreakdownTests` covers label totals summing to the same expenses (multi-label split, unlabeled, deleted labels, other currencies and excluded accounts left out), subcategories rolling up to their top level with its color, and folding the tail into "Other". `CategoryColorTests` pins the retuned palette.

Verified on an iPhone 18 Pro simulator, light and dark, with seeded sample data: every flat list screen (with footers, the first-row rule and segmented-control separators checked), the Accounts header, the Dashboard's balance card, account cards and their dark-mode fill, the Accounts card and Add tile, the three chart cards, the account detail screen, the retuned category colors beside the income/expense tiles, gradient category icons, and the launch view and system launch background. The palette was checked with the dataviz validator: every hard check passes in both modes, with sub-3:1 contrast warnings relieved by always-visible labels; ten colors cannot pass all-pairs separation, which is why charts name every part.

**Not verified:** taps and gestures could not be driven in the simulator, so the Labels side of the Expenses switch, the Balance Trend touch tooltip, tapping an account card or record, the Statistics filter sheet's interactions, the record editor's Delete row, discarding a split from an unsaved record, and the account icon picker were exercised only by build and unit tests. Account icon sync across devices and the production CloudKit schema for `symbolValue` are unverified.

Manual checks:

1. Drag across Balance Trend in light and dark mode; confirm the tooltip is readable and stays inside the chart.
2. Switch Expenses to Labels; confirm unlabeled spending appears as No label and the total matches Categories.
3. Tap an account card; step the period back and confirm the totals and records follow, and the next arrow stops at the current period.
4. Add a record, split it, then close without saving; confirm the split no longer appears in Splits.
5. Tap a record to edit it, delete it from the editor, and confirm the confirmation and the balance change.
6. Choose an icon for an account on one device and confirm it appears on a second device after sync, once the schema is deployed.
7. Cold-launch the app on a device in light mode; confirm no white flash before the launch view (delete and reinstall first, since iOS caches launch screens).

## Device Validation (2026-11-01)

Every feature in the README status table was tested on device by the project owner and passed, **except the Apple Watch companion**, which remains unbuilt (the watchOS platform is not installed) and unverified. This closes the device and visual checks the earlier entries left open: iCloud sync across devices, widgets on the home screen, Face ID/Touch ID and the passcode lock, the share sheet and document picker, every onboarding step, live exchange-rate downloads, Siri and Shortcuts, iPad and Mac layouts, notification delivery for budgets, bills, insights and debts, camera scanning and OCR, dashboard drag reordering, alternate app icons, drinking days, and the touch interactions listed under Interface Polish and Dashboard Validation.

Still open:

- **Apple Watch companion:** not compiled or embedded in the iOS app; its manual checks under Apple Watch Validation still apply.
- **CloudKit production schema:** the account icon field (`symbolValue`) must be deployed to the production environment before release. Device tests ran against the development environment.
- **iCloud wallet sharing (`CKShare`):** not implemented, so there is nothing to verify.

## Balance Adjustment Validation (2026-11-02)

**312 tests across 51 suites passed**, and unsigned iOS Simulator and macOS builds passed. The new `BalanceAdjustmentTests` suite covers increases and decreases changing the balance without a category, edit and delete reversing the effect, a transfer being rejected as an adjustment, statistics and account activity leaving adjustments out of income and expenses while balance history and statements include them, drafts encoded before the flag existed still decoding, and CSV export and import by direction.

**Not verified:** the app was not run, so the Adjust Balance button, the editor's Increase/Decrease mode and balance preview, and the adjustment row's icon and note were checked only by build. The `isAdjustment` attribute's CloudKit sync and production schema deploy are unverified.

Manual checks:

1. Open an account, choose Adjust Balance, enter an increase with a note such as "Interest", and confirm the preview matches the balance after saving.
2. Confirm the adjustment is listed with the plus-minus icon and its note, and the period's income and expense totals do not change.
3. Edit it into a decrease, then delete it, and confirm the balance follows each time.
4. Export a CSV and confirm the Type column reads `adjustment increase` or `adjustment decrease`.
5. Record an adjustment on one device and confirm it syncs to a second, once the schema is deployed.

### Account Balance Edits as Adjustments (2026-11-02)

Editing an account's balance now saves the difference as a balance adjustment instead of rewriting the opening balance. **314 tests across 51 suites passed**, and unsigned iOS Simulator and macOS builds passed. Two new tests cover a raised and then lowered balance producing one adjustment each while the statement's opening balance stays put, and a name-only edit producing no record. The existing account and record suites passed unchanged. Not run in the app.

Manual check: edit an account's balance, save, and confirm a "Balance adjustment · Balance edited" row appears for the difference, and that last month's balance history has not moved.

## App Icon Refresh (2026-11-02)

Replaced every icon with the new wallet-and-cards artwork: default, dark and tinted iOS icons, the seven macOS sizes and the 120/180 px Midnight, Forest and Sunset alternates. The iOS and alternate images are opaque with no alpha channel. The tinted icon sits on black, and the macOS icons are clipped to a rounded square with a transparent margin. Unsigned iOS Simulator and macOS builds passed with no icon warnings. Each rendered image was inspected, but none was seen on a Home Screen, Dock or in Settings.

Manual checks: confirm the icon in light, dark and tinted Home Screen modes; switch to each alternate in Settings and confirm the swatch color matches the icon; check the Dock icon on macOS.

## Large Amount Counting Setting (2026-11-03)

Added Settings → Currency → Count Large Amounts In (Automatic, Lakhs, Millions) for the totals inside the Dashboard and Statistics donuts. **315 tests across 51 suites passed**, and unsigned iOS Simulator and macOS builds passed. A new test covers the Lakhs and Millions choices applying to every currency and the lakh form falling back below one lakh. Not run in the app.

Manual check: with an MMK account spending over one lakh this month, switch the setting between Lakhs and Millions and confirm the Dashboard Expenses and Statistics donut totals change between "lakhs · MMK" and a K/M figure; with a USD account, confirm Lakhs shows lakhs there too.

### Chart Axes Follow the Counting Setting (2026-11-03)

The amount axis of the Dashboard balance and Balance Trend charts and of the Statistics charts now counts like the donut total ("50L" or "5M"). **316 tests across 51 suites passed**, and unsigned iOS Simulator and macOS builds passed. A new test covers the axis label under each choice and below one lakh. Not run in the app.

Manual check: switch Count Large Amounts In between Lakhs and Millions and confirm each chart's axis changes between "L" and K/M labels, while card and legend amounts stay exact.

### Widgets and Watch Follow the Counting Setting (2026-11-03)

`WalletSnapshot` now carries the `NumberScale`, and small widget and complication figures use it. **318 tests across 51 suites passed.** New tests cover the scale surviving the watch payload, an unknown scale from a newer build decoding as Automatic, and the compact currency form under each choice and below one lakh. Unsigned builds passed for the app on iOS Simulator and macOS, the `WalletWidgets` extension, and `WalletDomain` for watchOS.

**Not verified:** the `WalletWatch` and `WalletWatchWidgets` schemes do not build on `main`, before and after this change: `WatchWalletStore.swift` lacks `import Combine` and, once that is added, has Swift 6 data-race errors in its WatchConnectivity delegate. The complication edits were therefore not compiled. Nothing was run on a device, simulator or watch.

Manual check: with an MMK balance over one lakh, add the small Balance widget and the watch Balance complication, switch Count Large Amounts In between Lakhs and Millions, and confirm both change between "52.7L" and "5.3M".

## Watch Build Fix (2026-11-03)

`WalletWatch` and `WalletWatchWidgets` build again. `WatchWalletStore.swift` now imports Combine, and its WatchConnectivity delegate reads reachability, pending-transfer counts and the decoded snapshot on the delegate queue, passing only those `Sendable` values to the main actor instead of capturing `WCSession` and its payload dictionaries. Unsigned watchOS Simulator builds of both schemes passed with no warnings in the watch sources, which also compiles the complication edits from the entry above for the first time. The `My Wallet` scheme does not build the watch targets, so build them explicitly. Not run on a watch or simulator.

Manual checks: on a paired watch, confirm the app shows the phone's balance, the reachability state updates when the phone goes out of range, and a quick expense queues and then clears from the pending count once delivered.

## One Main Currency (2026-11-03)

Home Currency and Default Currency were merged into Main Currency. **320 tests across 51 suites passed**, and unsigned builds passed for the app on iOS Simulator and macOS and for `WalletWatch` and `WalletWatchWidgets` on watchOS Simulator. New tests cover carrying over existing settings (converting users keep their home currency, or the region's currency if never chosen; others keep their default; old keys removed) and a main currency outside the rate feed skipping downloads, leaving converted totals off and still converting with a record's own rate. The feed's currency list and its 404 for an MMK base were checked against the live API. Not run in the app.

Manual checks:

1. On a build from before this change, set Home Currency to USD, Default Currency to MMK and turn on converted totals; update and confirm Settings shows one Main Currency of USD.
2. Set the main currency to MMK with converted totals on and confirm Settings explains that automatic rates aren't published for MMK, with no download error.
3. Set it to USD with USD and EUR accounts and confirm the Dashboard shows a combined `≈` total, and that a new account, budget or goal starts in USD.

## Menu and Push Chevrons (2026-11-03)

Rows that open a menu now end in up-and-down chevrons and rows that push a screen keep a right chevron. `WalletMenuPicker` switched to the new `WalletMenuIndicator`, which changes List Density, Text Size, Auto-Lock, Send On and Time of Day at once. Count Large Amounts In moved from a plain `Picker` to `WalletMenuPicker`, so its value reads in secondary text like the rows around it. The Dashboard currency menu and the onboarding account Type menu also changed. `WalletMenuPicker` rows now make only the trailing value and chevrons the menu: the leading title stays outside it, so it no longer fades while the menu is pressed or open, and tapping the title no longer opens the menu. **320 tests across 51 suites passed**, and unsigned iOS Simulator and macOS builds passed. Not seen in the app.

Manual check: in Settings, confirm Main Currency shows a right chevron and pushes the currency list, while Count Large Amounts In, List Density, Text Size and Auto-Lock show up-and-down chevrons and open a menu in place. Tap each value and confirm its title stays fully visible while the menu is open.

### No Chevron on Rows That Open a Sheet (2026-11-03)

Removed the trailing chevron from every row that opens a sheet, full-screen cover or dialog rather than pushing a screen: account, budget, label, subcategory and drinking-day list rows and the balance-alert rows (each opens its editor as a sheet), the account and category editors' Icon rows, the account editor's Currency row, the record editor's Split with people and Photo rows, the receipts row, and onboarding's Currency field. Rows that push (record editor Account, Category and Label, the Statistics filter's Category, parent categories in the category picker, Settings' Main Currency) keep it. **320 tests across 51 suites passed**, and unsigned iOS Simulator and macOS builds passed. Not seen in the app.

Manual check: open Accounts, Budgets and Labels and confirm rows have no chevron yet still open their editor; in the record editor confirm Category still shows a chevron and pushes, while Split with people and Photo show none.

## Category Icons Sync Through iCloud (2026-11-03)

Category and subcategory icons moved from local preferences onto the category record (`CategoryRecord.symbolName`, optional) and the local `CategorySymbolStore` was removed. **325 tests across 51 suites passed** on two full runs, and unsigned builds passed for the app on iOS Simulator and macOS and for `WalletWatch` and `WalletWatchWidgets` on watchOS Simulator. New tests cover a chosen icon being stored on the category and surviving a fresh fetch while its name and nature stay unchanged, resetting to the starter icon, a choice winning over an older replica, a missing category being rejected, locally saved icons moving onto their categories once (a synced icon wins, unknown IDs are skipped, the local copy is removed), a failed save being reported, and backups carrying the icon while older backups still decode. The existing migration test that opens a store written before later fields still passes.

One unrelated run failed `screensSharingTheRecordsModelLoadItOnceBetweenThem`, which waits a fixed 50 ms for a reload; it passed alone three times and in both later full runs, so it is timing-sensitive under parallel load rather than affected by this change.

**Not verified:** iCloud sync between devices, and the production CloudKit schema, which still needs the new field deployed. Not run in the app.

Manual checks:

1. On a build from before this change, give a category a custom icon; update and confirm the icon is still there.
2. On two signed devices with the same iCloud account, change a subcategory's icon on one and confirm it appears on the other after sync, then reset it and confirm both return to the starter icon.
3. Confirm the new icon shows in the category list, record rows and the Recent Records widget.

## Delete Account from the Editor (2026-11-03)

The account editor gained a Delete Account row in its own section at the end, shown only when editing. It opens the existing deletion impact sheet; after a delete the sheet closes, then the editor, then the account's detail screen when the editor was opened from there. The deletion logic is unchanged and already covered. **320 tests across 51 suites passed**, and unsigned iOS Simulator and macOS builds passed; after rebasing onto the category icon change, **325 tests** and both builds passed again. The presentation sequence is UI-only and was not run in the app.

Manual checks:

1. Accounts → tap an account → Delete Account → Keep as unlinked records → Delete Account → Delete; confirm the sheets close and the account is gone from the list.
2. Dashboard → tap an account card → Edit → Delete Account → delete; confirm you land back on the Dashboard, not on "Account unavailable".
3. Open Delete Account, then Cancel; confirm the editor stays open with its edits intact.
4. Create Account shows no Delete Account row.

## Chevrons Back on Rows That Open a Sheet (2026-11-03)

Without a chevron, rows such as a category's subcategories did not read as tappable, so the right chevron is back on every row that opens something, whether it pushes or presents a sheet. This reverses the code of the earlier "No Chevron on Rows That Open a Sheet" entry on all 13 rows (account, budget, label, subcategory, drinking-day and balance-alert rows; Icon in the account and category editors; Currency in the account editor; Split with people and Photo; receipts; onboarding Currency), and the same rule was applied to rows that never had one: the Debts and Goals list rows and the App Lock Passcode row. The account editor's Currency row now uses the shared `WalletDisclosure` instead of a hand-drawn chevron. Rows still open what they did; nothing moved from a sheet to a pushed screen. **325 tests across 51 suites passed**, and unsigned iOS Simulator and macOS builds passed. Not seen in the app.

Manual check: open a category with subcategories and confirm each subcategory row shows a chevron and opens its editor; confirm the same on Accounts, Budgets, Labels, Debts, Goals and Drinking Days, and on Settings → Passcode.

### Chevrons on Record Rows (2026-11-03)

`RecordRow` now ends in a chevron after the amount and its paperclip, so the Records list, the Dashboard's recent records and an account's activity all show it from one change; each of those rows opens the record editor. **325 tests across 51 suites passed**, and unsigned iOS Simulator and macOS builds passed. Not seen in the app; check that long amounts still fit beside the chevron on a small phone.

Manual check: in Records, on the Dashboard and in an account's detail, confirm each record row shows a chevron and still opens its editor, and that a large amount such as 1,234,567,890 MMK is not truncated.

## Day Headers in Search Results (2026-11-03)

Search results, sorted by relevance, now show day section headers like the unfiltered list. Ranked results are regrouped by calendar day, newest day first, keeping the best match first within each day; amount sorts stay ungrouped. The sort hint in the filter sheet explains this while search text is entered. The day header's net counts only the matching records on that day. **326 tests across 51 suites passed**, and unsigned iOS Simulator and macOS builds passed. The updated grouping test and a new one cover search results being grouped, days running newest first, and the best match leading each day. Not run in the app.

Manual check: search for a payee or category that appears on several days and confirm headers read Today, Yesterday and older dates in order, that a day's strongest match is listed first, and that Largest or Smallest sorting still shows a flat list.

## Account Numbers (2026-11-03)

Accounts of every type but Cash can hold an optional number (Card Number, Loan Number or Account Number by type), stored whole in a new defaulted `AccountRecord.accountNumberValue` marked `.allowsCloudEncryption` (end-to-end encrypted in iCloud), shown as `•••• 1234` in the Accounts list and on the account screen, and copied from the account screen to a device-only clipboard entry that expires after a minute on iOS. **331 tests across 52 suites passed**, and unsigned builds passed for the app on iOS Simulator and macOS and for `WalletWatch` and `WalletWatchWidgets` on watchOS Simulator; after rebasing onto the search day headers change, **332 tests** and the iOS Simulator and macOS builds passed again. A new `AccountNumberTests` suite covers which types have a number and its titles, trimming, the allowed characters and length, masking past separators, saving the whole number, clearing it when emptied or when the account becomes Cash, rejecting an invalid number without saving, JSON backups carrying it while older backups still decode, and the schema marking that field, and only that field, encrypted in iCloud. Existing account migration tests, which open a store written before later fields, still pass.

**Not verified:** iCloud sync of the new field and its production CloudKit schema deploy. In the CloudKit Console the field should appear in the encrypted section of `CD_AccountRecord`; confirm that in the development schema before deploying, since encryption cannot be changed afterwards. Also unverified: the clipboard's device-only and expiry behavior, and the screens themselves; nothing was run in the app.

Manual checks:

1. Edit a Checking account, enter `0012 3456 7890`, save, and confirm Accounts shows `Checking Account · •••• 7890`.
2. Confirm the field is titled Card Number for a credit card and Loan Number for a loan, and disappears when the type is set to Cash; save as Cash and confirm the number is gone when switching back.
3. Open the account, tap the number row, confirm it shows "Copied", paste elsewhere to check the full number, and confirm on iOS it is no longer pasteable after a minute and does not reach a Mac through Universal Clipboard.
4. Enter `12/34` and confirm saving reports the allowed characters.

## Saves Update in Place Instead of Reloading (2026-11-03)

Saving, editing or deleting one record now updates the record list and account balances in memory instead of reading the whole wallet back. Before, one save caused three full reloads: `RecordsViewModel.save` awaited a reload, the repository's change notice started a second, and `NSPersistentStoreRemoteChange`, which a probe showed is posted for the app's own saves and not only iCloud imports, started a third. Each reload read every record twice, once for the list and once to sum balances, and `AccountsViewModel` did its own full sum as well. Measured in a temporary release-build benchmark at 10,000 records on the development Mac: a full reload took 0.51 s, and a save now takes **13 ms** end to end with no reload. The benchmark was deleted after the run.

**342 tests across 53 suites passed** on three consecutive full runs, and unsigned builds passed for the app on iOS Simulator and macOS and for `WalletWatch` and `WalletWatchWidgets` on watchOS Simulator. The new `IncrementalRecordUpdateTests` cover:

- date-ordered splicing, including an edit that moves a record's date
- applying the same change twice being harmless
- balance deltas for an expense edited into a transfer and back
- a save, edit and delete through the view model with no record or account fetch, and balances equal to the store's own sum after each step
- a record written elsewhere (as the watch or Shortcuts do) arriving by notice without a reload
- an unknown change still reloading
- account balances following record changes without a reload
- a reload landing between a save and its notice not counting the save twice
- the store's own saves not triggering a reload

`screensSharingTheRecordsModelLoadItOnceBetweenThem` now waits for its load instead of a fixed 50 ms, which a busy parallel run could outlast; it still checks that one change causes exactly one load. A first version of the account update double-counted a change when a reload landed between a save and its notice; that is what led to ledger versions, and the race test now covers it.

**Not verified:** on a device with iCloud, that CloudKit imports are written with an author (`NSCloudKitMirroringDelegate.import`) and so still reload. If an import were written without an author it would be skipped and show only after the next foreground reload. Not run in the app.

Manual checks:

1. With iCloud on two devices, add a record on one and confirm it appears on the other without leaving the screen.
2. Add, edit and delete records and confirm the Records list, Dashboard balance and Accounts balances update straight away and match after a pull to refresh.
3. In Instruments (Time Profiler), with a large wallet, confirm a save no longer shows `fetchRecords` or `fetchAccounts`.

## SwiftLint Configuration (2026-11-03)

SwiftLint 0.65.1 was installed and run. With default rules it reported 523 violations (42 errors) in 125 files, nearly all where the defaults conflict with the project's established style, and no bugs. The new `.swiftlint.yml` sets limits from measurements of the code:

- line length 160 (99% of lines are 125 characters or fewer) and an error limit of 500, above the longest single-line strings
- type length 400, file length 500, function body length 80
- tuples of up to 4 members and up to 6 function parameters
- short names allowed (`a`, `b`, `x`, `y`, `id`, `to`) and `My_WalletApp` exempted
- `trailing_comma` and `statement_position` disabled, since trailing commas and compact one-line `if`/`else` chains are deliberate

The remaining **69 warnings and 0 errors** are long lines, the two largest screens (`HomeView`, `RecordEditorView`), and six complex functions, which is an accurate list of what is worth splitting later.

Small cleanups made:

- `RecurringView` builds an occurrence's draft in a helper instead of a `let _ =` assignment inside a view builder, and falls back to the draft's date instead of force-unwrapping the rule's.
- Removed a doubled trailing newline, an explicit `= nil` and redundant parentheses in a `guard`.
- CSV decoding states that Latin-1 accepts any bytes instead of keeping an unreachable lossy fallback.
- Two tests decode strictly, so invalid bytes fail them instead of hiding what they check for.
- The Delete Account sheets name their dismiss handlers instead of passing an inline closure next to the trailing content.

**342 tests across 53 suites passed**, and unsigned iOS Simulator and macOS builds passed with no compiler warnings.

## Bank Statement CSV Import (2026-11-03)

CSV import now reads bank statement exports: bank header names, signed amounts or Debit/Credit columns, files without an Account column (an account is chosen first), day-first dates and date-only rows. **358 tests across 56 suites passed**, and unsigned builds passed for the app on iOS Simulator and macOS and for `WalletWatch` and `WalletWatchWidgets` on watchOS Simulator. SwiftLint reports 68 warnings, down from 69; none are new.

The new suites are `BankStatementImportTests`, `DateOnlyDuplicateTests` and `BankStatementImportViewModelTests`; the coverage table lists what they check. Two existing tests changed on purpose. `missingRequiredColumnsAreReported` now expects only Account to be missing from a Date and Amount file, because Type is optional when amounts carry a sign. `ImportPlannerTests` rows now carry a category, because rows without one are now flagged.

**Defect found and fixed:** the view-model test showed that every income or expense row without a matching category passed the preview as importable, then failed at save with "Choose a category or subcategory". This affected the app's own CSVs without a Category column before this change, and it would have hit every bank row. The planner now lists such rows under "Cannot import" until a fallback category is chosen for their kind.

**Not verified:** the app was not run, so the account choice dialog, the "Amounts are spending" toggle and the fallback category pickers were checked only by build and unit tests. No real bank export was tried; the fixtures are modelled on common layouts.

Manual checks:

1. Export a statement from your bank as CSV, import it, choose the account, and confirm the payees, amounts, directions and dates (especially day/month order) in the preview.
2. For a card statement that lists purchases as positive, turn on "Amounts are spending" and confirm the preview flips.
3. Choose an expense fallback category, import, then import the same file again and confirm every row is reported as already in your wallet.
4. Confirm that cancelling the account dialog or the review sheet leaves nothing behind, and that the next import starts clean.

## Matching Manual Entries on Bank Import (2026-11-03)

Bank statement rows are now matched to records entered by hand. A match needs the same account, direction and amount, and a record dated the same day or up to three days before the row. Transfers count on both accounts. **366 tests across 57 suites passed**, and unsigned builds passed for the app on iOS Simulator and macOS and for `WalletWatch` and `WalletWatchWidgets` on watchOS Simulator. SwiftLint still reports 68 warnings, none new.

`ManualEntryMatchingTests` covers:

- a record at any time of the same day matching
- records up to three days earlier matching, but not four days earlier or a day later
- account, direction and amount each having to agree
- same-day matches being made before lagged ones, which matching row by row would get wrong
- the closest earlier record winning
- a transfer matching both accounts' statements at its sent and received amounts
- Import Anyway freeing the matched record for another row

A view-model test matches a purchase entered by hand two days before the bank date, then overrides it and checks that cancelling clears the override. The existing `DateOnlyDuplicateTests` pass unchanged.

**Not verified:** the app was not run, so the "Matched to your records" section and its Import Anyway button were checked only by build and tests.

Manual checks:

1. Enter a few purchases by hand, then import a bank statement covering those days. Confirm they appear under "Matched to your records" with the right dates and are not imported again.
2. Enter a transfer between two accounts, then import each account's statement. Confirm the transfer is matched in both.
3. Tap Import Anyway on a matched row and confirm it moves to Ready to import.

## Near-Amount Matching on Bank Import (2026-11-03)

Bank rows now also match records whose amount is within 5% of the bank's, after every exact match has been made. **371 tests across 57 suites passed**, and unsigned builds passed for the app on iOS Simulator and macOS and for `WalletWatch` and `WalletWatchWidgets` on watchOS Simulator. SwiftLint still reports 68 warnings, none new.

New tests in `ManualEntryMatchingTests` cover:

- a 103.50 charge matching a 100 record, with the entered amount reported, while 105.50 does not match
- an exact match reporting no difference
- an exact amount within the lag beating a near amount on the same day
- a near row earlier in the file not taking another row's exact match
- the closest of several near amounts being chosen
- a transfer's received amount matching within the tolerance

`aTransferEnteredByHandMatchesBothAccountsStatements` now uses a received amount of 80 instead of 98. Within the tolerance a 100 credit would match 98, so the old figure no longer showed that the destination leg uses the received amount.

**Not verified:** the app was not run, so the entered amount shown in "Matched to your records" was checked only by build. Matching speed on a large wallet was not measured. The new day index reads at most four days of records per row, where before it scanned every record in the account with that amount.

Manual checks:

1. Enter a purchase at a round figure, then import a statement where it settled slightly higher, for example with a foreign-transaction fee. Confirm the row is matched and the review shows the amount you entered.
2. Confirm that a purchase with a tip of 15% or more is not matched, and that Import Anyway still works on a near match you judge wrong.

## Tips and Updating Records to the Bank's Amount (2026-11-03)

An expense bill now also matches a bank charge up to 25% higher (a tip), tried last and only against records no other row matched. By default the import changes each matched record's amount to the bank's. **380 tests across 58 suites passed**, and unsigned builds passed for the app on iOS Simulator and macOS and for `WalletWatch` and `WalletWatchWidgets` on watchOS Simulator. SwiftLint still reports 68 warnings, none new.

New tests in `ManualEntryMatchingTests` cover:

- a 60 charge matching a 50 bill as a tip with an update from 50 to 60, while 62.60 (25.2%) and a lower charge do not match
- tips not applying to income, transfers or balance adjustments
- a bill's own exact row being matched before any tip
- a near amount being preferred over a tip
- near matches producing an update while exact ones do not
- a same-currency transfer matching without an update
- a cross-currency transfer updating its received amount and its sent amount from each account's statement

`TipImportViewModelTests` uses an in-memory store. It covers:

- a tipped dinner taking the bank amount, keeping its payee and receipt photo, and moving the balance to -60, with nothing imported
- turning updates off leaving the record at 50
- a split dinner keeping its amount, with the split still totalling 50, and being reported

Two existing tests changed amounts on purpose. A 105.50 charge against a 100 bill, and a 5 charge against a 4 bill, are now tips. Their "does not match" checks use 94.50 and 6 instead.

**Defect found and avoided:** loaded records carry no photo bytes, only a `hasPhoto` flag, and saving writes the photo. Updating an amount straight from the loaded record would have erased its receipt. The update reloads the photo first, as the record editor does, and a test checks the photo survives.

**Not verified:** the app was not run, so the update toggle, the "Will change to" text, the Update button for statements with only amount changes, and the result labels were checked only by build.

Manual checks:

1. Enter a restaurant bill without the tip, then import a statement where it posted with the tip. Confirm the review shows the tip and the new amount, and that after import the record and the account balance match the bank.
2. Repeat with the update toggle off and confirm the record is unchanged.
3. Split a bill with someone, then import its tipped charge. Confirm the record keeps its amount and the result explains why.
4. Confirm a record with a receipt photo still has it after its amount is updated.

## Categories by Payee (2026-11-04)

Bank rows without a category now take the category last used for their payee, and a new record in the editor takes it when a payee is entered. **389 tests across 60 suites passed**, and unsigned builds passed for the app on iOS Simulator and macOS and for `WalletWatch` and `WalletWatchWidgets` on watchOS Simulator. SwiftLint still reports 68 warnings, none new. The two existing `RecordEditorView` length warnings grew by 10 lines.

New tests in `PayeeCategorizerTests` cover:

- "STARBUCKS #1234", "POS STARBUCKS 0042" and "GRAB*TRIP SINGAPORE SG" matching payees typed as "Starbucks" and "Grab", while "Grabbing Lunch" does not
- accented and Burmese payees
- the longest known start of a description winning ("Grab Food" over "Grab")
- the most recent record for a payee winning
- income and spending being learned separately
- transfers, adjustments, uncategorised records and deleted categories teaching nothing
- processor words alone ("CARD PAYMENT") naming no payee
- an import row taking the learned category before the fallback, a category named in the file winning over both, and a learned row not needing a fallback

`PayeeCategorizerViewModelTests` uses an in-memory store. It covers a saved record updating the cached suggestions without a reload, the review's category preview, the toggle switching rows back to the fallback, and the imported records keeping the learned category.

**Not verified:** the app was not run, so the review toggle, the category in the preview rows and the editor filling in the category were checked only by build.

Manual checks:

1. Enter an expense with payee "Starbucks" under a coffee category. Import a statement with a "STARBUCKS #0042" row and confirm the review shows that category beside it and counts it in the toggle's footer.
2. Turn the toggle off and confirm the row uses the expense fallback; turn it back on.
3. Add a new expense, leave the category empty and enter payee "Starbucks". Confirm the category fills in, and that changing the payee to an unknown one clears it again.
4. Choose a category first, then enter the payee, and confirm your choice is kept. Edit a saved record's payee and confirm its category does not change.

## Payee Suggestions (2026-11-04)

The Payee screen in the record editor now lists past payees for the record's kind as you type. **397 tests across 62 suites passed**, and unsigned builds passed for the app on iOS Simulator and macOS and for `WalletWatch` and `WalletWatchWidgets` on watchOS Simulator. SwiftLint still reports 68 warnings, none new. The two existing `RecordEditorView` length warnings grew by 9 lines.

New tests in `PayeeSuggestionsTests` cover:

- matching the start of a payee or of any word in it ("COF" finds "Blue Bottle Coffee", "ele" finds "7-Eleven"), but not the middle of a word ("ucks")
- ignoring accents and case
- "Starbucks", "STARBUCKS #0042" and "STARBUCKS #0051" offered once, as "Starbucks"
- payees the text starts listed first, then the most used
- the most recent payees offered when nothing is typed, up to the limit
- a payee typed in full not being offered back
- payees kept per kind, with adjustments and blank payees left out

`PayeeSuggestionsViewModelTests` uses an in-memory store and covers a saved record's payee being offered without a reload.

**Not verified:** the app was not run, so the suggestion list, its category detail and choosing a suggestion were checked only by build.

Manual checks:

1. Add an expense, open Payee with nothing typed, and confirm recent payees are listed under "Recent".
2. Type the first letters of a known payee and confirm it is listed under "Suggestions" with its category. Choose it and confirm the form shows the payee and the filled-in category.
3. Choose a category first, then open Payee, and confirm the suggestions show no category.
4. Switch to Income and confirm only income payees are offered.

## Payee Suggestions Device Check (2026-11-04)

The user ran the four manual checks from Payee Suggestions (2026-11-04) in the app, and all four passed: recent payees listed with nothing typed, a typed payee suggested with its category and filling both in when chosen, no category shown once one was chosen, and only income payees offered for income.

Check 2 also covers the editor filling in the learned category when a suggestion is chosen. The Categories by Payee (2026-11-04) checks are still not run on a device: the import review toggle and preview, typing a payee in full, and editing a saved record.

## Payer Label, Suggestions Across Kinds and Faster Payee Screen (2026-11-04)

The user reported that income offered no payees and that the Recent list lagged as the Payee screen opened. **401 tests across 62 suites passed** (an earlier count of 402 across 63 included the throwaway timing test), and unsigned builds passed for the app on iOS Simulator and macOS and for `WalletWatch` and `WalletWatchWidgets` on watchOS Simulator. SwiftLint still reports 68 warnings, none new. The two existing `RecordEditorView` length warnings grew by 2 lines.

**Measurement:** a throwaway timing test (deleted afterwards) built both structures from 10,000 records with 300 distinct payees, in a release build on a Mac. Before: 18 ms for suggestions and 17 ms for categories, paid on the main thread when Payee first opened. After keying each distinct payee text once: 1.5 ms and 2.0 ms. Six lookups took under 0.1 ms both times. The editor now also builds both in the background when it opens.

The new and changed tests in `PayeeSuggestionsTests` cover:

- the record's own kind coming first, with other kinds filling the remaining places, for typed and empty text and under a limit
- income with no payers of its own still offering the wallet's payees
- a payee recorded under two kinds being offered once
- adjustments and blank payees being left out, and surrounding spaces trimmed

The new `PayeeSuggestionsViewModelTests` test covers data built in the background being used, and a record saved afterwards still being suggested and categorised. The earlier test that expected income payees never to be offered on an expense was replaced, since that is now intended.

**Not verified:** the app was not run, so the Payer label and the lag were not checked in the app; the lag fix is measured only on a Mac.

Manual checks:

1. Add an income and confirm the row and screen say Payer and the caption says "Add payer".
2. On an income with no payers recorded yet, open Payer and confirm your expense payees are offered; record an income from someone, then confirm they are listed first next time.
3. With your full wallet, open Add Record, then Payee, and confirm the Recent list appears without a stutter.

## First Keyboard of a Launch (2026-11-04)

On device, the user found that the first push to Payee in a launch still lagged during the slide, and later pushes did not. Opening Note first lagged the same way, which ruled out the payee data: the cause is iOS loading the letter keyboard (autocorrect and predictions) the first time it appears in a launch, which the amount field's number pad does not do. `RecordTextEntry` raised the keyboard during the push. The first text screen of a launch on iOS now waits 0.4 seconds, just past the push, before focusing its field; later screens focus at once as before, and macOS is unchanged. 401 tests passed, unsigned iOS Simulator and macOS builds passed, and SwiftLint still reports 68 warnings.

**Not verified:** not yet run on the device.

Manual check: launch the app fresh, open Add Record, then Payee (or Note). The slide should be smooth, with the keyboard rising just after it ends. Go back and open it again: the keyboard should rise with the slide.

## Scrolling Dismisses the Record Keyboard (2026-11-04)

At the user's request, scrolling the record form up or down now dismisses the amount keyboard at once (`.scrollDismissesKeyboard(.immediately)`). Before, it was `.interactively`, which dismissed the keyboard only when the drag reached down into the number pad. 401 tests passed, the unsigned iOS Simulator build passed, and SwiftLint still reports 68 warnings.

**Not verified:** not yet run on the device.

Manual check: open Add Record with the amount keyboard up, then scroll the form up and down. The keyboard should go away as soon as the scroll starts, in either direction, and tapping the amount should bring it back.

## Payee Work Device Check (2026-11-04)

After the payee work reached `main` at 6a63c66, the user ran every outstanding manual check on the device, and all passed:

- Categories by Payee (2026-11-04): the import review's "Use categories from past records" toggle and the category shown beside each row, typing a known payee in full and changing it to an unknown one to clear the category, choosing a category first, and editing a saved record without its category changing
- Payer Label, Suggestions Across Kinds and Faster Payee Screen (2026-11-04): Payer on income, an income with no payers yet offering the wallet's other payees, and the Recent list appearing without a stutter
- First Keyboard of a Launch (2026-11-04): a smooth first push to Payee or Note after a fresh launch
- Scrolling Dismisses the Record Keyboard (2026-11-04): scrolling either way dismissing the keyboard

These entries' "Not verified" notes are superseded by this check. The bank import's earlier matching and tip checks from 2026-11-03 were not part of this run, so the README's Export and import row keeps their device check pending.

## Cash-Flow Forecast (2026-11-04)

Each account's balance is projected over the next 30 days from its recurring series and unpaid bills, on a new Dashboard card with a detail sheet. **413 tests across 64 suites passed**, and unsigned builds passed for the app on iOS Simulator and macOS and for `WalletWatch` and `WalletWatchWidgets` on watchOS Simulator. SwiftLint still reports 68 warnings, none new. The two existing `HomeView` length warnings grew by 2 lines.

New tests in `CashFlowForecastTests` use a fixed UTC calendar and cover:

- a weekly series contributing days 1, 8, 15, 22 and 29 from its next index, with running balances, the lowest point and no warning
- a skipped occurrence dropped, a modified one moved to its own date and amount, and an already-generated one dropped; an untitled record taking its category's name
- paused, cancelled and finished (count reached) series contributing nothing
- an occurrence already due landing today as overdue
- unpaid bills, repeating and one-off, as expenses on their account; a paid bill dropped; an overdue bill landing today
- a bill within three days of a recurring expense of the same amount counted once, while a bill of another amount is counted
- a transfer moving both accounts, and an account with nothing planned left out
- thresholds: zero for cash, checking and savings; none for cards and loans unless a minimum is set; the minimum when set
- the first fall below the threshold, below a set minimum, already below today, and none for a card
- day-by-day balances from the start of today to the last day, ending at the ending balance

`CashFlowForecastViewModelTests` uses an in-memory store. It covers accounts forecast to fall below zero coming first, soonest first, and the card being in the default arrangement right after Upcoming Bills and introduced there into an older saved arrangement.

**Not verified:** the app was not run, so the card, its rows, the detail sheet and its chart were checked only by build.

Manual checks:

1. With a recurring expense and a bill on a checking account, open the Dashboard and confirm the Next 30 days card lists it with its balance in 30 days. Tap it and confirm the chart and the Planned list, with the balance after each item.
2. Add a bill large enough to take the account below zero within 30 days. Confirm the row turns red with the date and balance, that the account moves to the top, and that the detail sheet shows the warning.
3. Create a bill with the same amount as a recurring expense on the same account, due a day after it. Confirm only one of the two is listed.
4. Skip the next occurrence of a series in Recurring and confirm it leaves the forecast; pause the series and confirm all its items leave.
5. Pay a bill with Mark Paid and Add Expense and confirm the forecast no longer lists that occurrence, while the balance today has dropped by its amount.
6. Confirm a credit card with charges planned shows its lowest point but no red warning, until a minimum-balance alert is turned on for it.
7. Confirm that on an existing install the card appears right after Upcoming Bills, and can be hidden and reordered in Edit Dashboard.
