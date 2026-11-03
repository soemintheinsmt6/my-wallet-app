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
| `BalanceAdjustmentTests` | Adjustment increases/decreases changing balances without a category, account balance edits recorded as adjustments without shifting earlier history (and none for a name-only edit), edit/delete reversal, transfers rejected as adjustments, totals excluding adjustments while balance history and statements include them, older drafts decoding and CSV round-tripping |
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
