# Feature Implementation Roadmap

Future features planned for **My Wallet**, grouped by priority phase. Each feature includes its scope, the modules it touches, and any dependencies on other features or infrastructure.

---

## Phase 1 — Core Gaps

These features close the gaps listed in the current Feature Status table and are prerequisites for a complete v1.0.

---

### 1.1 Record Editing

> **Status:** Implemented locally; visual/device verification pending
> **Modules:** `WalletDomain/Records`, `WalletData`, `WalletFeature/Records`

Allow users to open a saved record, modify any field (amount, category, account, date, tags, note, payee, payment type, photo) and save the changes. Balance adjustments must be recalculated atomically: reverse the old record's effect, apply the new values. Changing the account or switching between expense/income/transfer must handle the debit/credit swap correctly.

- [x] Add `updateRecord` to `RecordRepository` and `RecordUseCases`
- [x] Reuse `RecordEditorView` in edit mode, pre-populated from the existing `WalletRecord`
- [x] Atomic balance recalculation on account changes
- [x] Validate that photo replacement and removal work correctly
- [x] Unit tests for balance adjustment edge cases

---

### 1.2 Record Deletion

> **Status:** Implemented locally; visual/device verification pending
> **Modules:** `WalletDomain/Records`, `WalletData`, `WalletFeature/Records`

Delete a single record with confirmation. Reverse its balance effect on the associated account(s). Support swipe-to-delete and context-menu delete from the records list, plus a delete button in the detail view.

- [x] Add `deleteRecord` to `RecordRepository` and `RecordUseCases`
- [x] Confirmation alert before deletion
- [x] Balance reversal logic (expense adds back, income subtracts, transfer reverses both sides)
- [x] Remove associated photo data from storage
- [x] Unit tests for deletion and balance reversal

---

### 1.3 Account Deletion

> **Status:** Implemented locally; visual/device verification pending
> **Modules:** `WalletDomain/Accounts`, `WalletData`, `WalletFeature/Accounts`

Delete an account with full disclosure of the consequences. Show the number of records that will be orphaned or deleted. Offer two strategies: delete all associated records, or keep records as archived/unlinked entries. Transfers involving the deleted account need explicit handling.

- [x] Add `deleteAccount` to `AccountRepository` and `AccountUseCases`
- [x] Impact summary before confirmation (record count, balance)
- [x] Cascade or archive strategy selection
- [x] Handle transfer records referencing the deleted account
- [x] Unit tests for cascade and archive paths

---

### 1.4 Category Deletion

> **Status:** Implemented locally; CloudKit device verification pending
> **Modules:** `WalletDomain/Categories`, `WalletData`, `WalletFeature/Categories`

Delete a root category or subcategory. Deleting a root category should offer to reassign its subcategories or delete them. Records using a deleted category/subcategory should fall back to an "Uncategorized" state rather than losing data.

- [x] Add `deleteCategory` to `CategoryRepository` and `CategoryUseCases`
- [x] Reassign-or-delete prompt for subcategories under a deleted parent
- [x] Graceful fallback for records referencing deleted categories
- [x] Prevent deletion of the last remaining category
- [x] Unit tests for reassignment and orphaned-record handling

---

### 1.5 Statistics Dashboard

> **Status:** Implemented locally; visual/device verification pending
> **Modules:** `WalletDomain` (new `Statistics/`), `WalletFeature` (new `Statistics/`)

A dedicated tab or section showing spending and income analytics. Reuse `category.colorToken.color` for chart marks as noted in the design system.

- [x] Total income vs. total expenses for a selected period (week, month, year, custom)
- [x] Expense breakdown by category — pie/donut chart with category colors
- [x] Income breakdown by category
- [x] Daily/weekly/monthly spending trend — bar or line chart
- [x] Account balance history over time
- [x] Top spending categories ranking
- [x] Filter by account, category, tag, date range
- [x] Respect `excludeFromStats` account setting
- [x] Swift Charts integration

---

Implementation notes (2026-09-06): Phase 1 is implemented. Statistics keeps currencies separate; automatic conversion remains Phase 3.6. Balance history is reconstructed from current base balances and the ledger, so manual balance corrections apply retrospectively. Category deletion adds an optional `deletionDate` tombstone to preserve deleted starter IDs across reseeding. Archived account records retain currency snapshots and surviving transfer legs; editing an unlinked record requires selecting valid accounts again. Phase 2 is implemented below; Phases 3–5 remain planned.

## Phase 2 — Financial Intelligence

Features that help users understand and control their finances beyond basic tracking.

---

### 2.1 Budgets

> **Status:** Implemented locally; notification/device verification pending
> **Modules:** `WalletDomain` (new `Budgets/`), `WalletData`, `WalletFeature` (new `Budgets/`)

Set monthly or custom-period spending limits per category or overall. Track progress against the budget with visual indicators.

- [x] `Budget` entity: amount, period (monthly/weekly/custom), linked category or global
- [x] `BudgetRepository` and `BudgetUseCases`
- [x] Budget progress bar in the dashboard and category detail
- [x] Notifications when approaching or exceeding a budget limit
- [x] Rollover option for unused budget amounts
- [x] Budget vs. actual comparison view

---

### 2.2 Recurring Transactions

> **Status:** Implemented locally; notification/device verification pending
> **Modules:** `WalletDomain/Records` (extend), `WalletData`, `WalletFeature/Records`

Define transactions that repeat on a schedule. The app creates records automatically or prompts the user to confirm.

- [x] `RecurrenceRule` value type: frequency (daily/weekly/biweekly/monthly/yearly), end date or count
- [x] Attach recurrence to a `RecordDraft`
- [x] Background task or app-launch hook to generate due records
- [x] Upcoming recurring transactions list
- [x] Edit/pause/cancel a recurring series
- [x] Skip or modify individual occurrences

---

### 2.3 Financial Reports

> **Status:** Implemented locally; notification/device verification pending
> **Modules:** `WalletFeature` (new `Reports/`)

Generate downloadable or shareable reports summarizing financial activity.

- [x] Monthly/yearly summary report (income, expenses, net, top categories)
- [x] Category-level breakdown report
- [x] Account statement view with running balance
- [x] Export as PDF or share via system share sheet
- [x] Date range selection for custom reports

---

### 2.4 Bill Reminders

> **Status:** Implemented locally; notification/device verification pending
> **Modules:** `WalletDomain` (new `Reminders/`), `WalletData`, `WalletFeature` (new `Reminders/`)

Track upcoming bills and due dates with push notification reminders.

- [x] `BillReminder` entity: name, amount, due date, recurrence, linked category/account
- [x] Local notification scheduling (1 day before, on due date, configurable)
- [x] Mark as paid — optionally auto-create a record
- [x] Overdue bill highlighting
- [x] Calendar view of upcoming bills

---

Implementation notes (2026-09-06): Phase 2 adds a Planning tab for budgets, recurring series, bills and reports. Monthly/weekly budgets are anchored to their start date, use included accounts in one currency, and roll over only positive unused funds. Recurring records are generated on launch/foreground or manual refresh in batches of up to 500 per series; later records do not block behind postponed individual occurrences. Occurrence receipts prevent local retries or record deletion from regenerating charges. Notification permission is explicitly requested from the budget/bill editor; the nearest 60 eligible notices are scheduled/refreshed on app activity. Reports include native paginated PDF export and currency-separated summaries. Four additive SwiftData models store Codable payloads; signed-device CloudKit and notification delivery still require verification.

## Phase 3 — User Experience Enhancements

Polish and convenience features that make daily use smoother.

---

### 3.1 Search and Filtering

> **Status:** Implemented locally; visual/device verification pending
> **Modules:** `WalletDomain/Records`, `WalletFeature/Records`

Full-text search across records with advanced filtering.

- [x] Search by note, payee, amount, category name, tag name
- [x] Filter by date range, record type, account, category, tag, payment type
- [x] Combine search with filters
- [x] Recent searches history
- [x] Results sorted by relevance or date

Implementation notes (2026-09-10): `RecordSearch` is a pure domain calculation over the records already loaded by `RecordsViewModel`; there is no new persistence or repository contract. Every whitespace-separated term must match at least one of payee, note, category name (including its parent), label name or amount, compared case- and diacritic-insensitively. Filter groups intersect while values inside a group union; selecting a root category includes its subcategories and excludes uncategorized records, and an account filter matches either leg of a transfer. Date ranges are start-inclusive/end-exclusive and amount bounds are inclusive, comparing the record's own amount without currency conversion. Relevance falls back to newest-first without search text, and all orders break ties deterministically. Recent searches are a capped, newline-separated local preference cleared by Reset Wallet Data; they do not sync.

---

### 3.2 Home Screen Widgets

> **Status:** Implemented locally; on-device widget rendering verification pending
> **Modules:** `WalletDomain` (new `Widgets/`), `WalletFeature` (new `Widgets/`), new `WalletWidgets` extension target

Glanceable financial summaries on the home screen.

- [x] Total balance across accounts widget (small/medium)
- [x] Monthly spending summary widget
- [x] Recent transactions widget (medium/large)
- [x] Budget progress widget
- [x] Quick-add record widget deep-linking into the editor with the kind preselected

Implementation notes (2026-09-10): The extension never opens the wallet's SwiftData store. Doing so would mean relocating the CloudKit-backed store into a shared App Group container and migrating existing installs, so instead the app writes a resolved `WalletSnapshot` — balances per currency, this month's totals, recent records, budget progress — into `group.com.app.My-Wallet` and the widget only reads it. Titles, symbols and category colors are resolved by the app, so the extension links `WalletDomain` alone and carries no presentation logic. Writes are atomic (temporary file plus replace) so a reload landing mid-write cannot see a truncated file, and a missing container is never fatal: the app keeps working and widgets keep their previous summary.

`WalletSnapshotCoordinator` observes both view models, debounces 400 ms because one save publishes several times, skips writing when nothing the widgets show has changed, and then reloads timelines. Resetting wallet data clears the snapshot through `SettingsViewModel.onReset`. Timelines refresh hourly purely as a fallback for when the app has not run.

Widgets lead with the currency holding the most accounts, ties broken by code so the figure never flickers between refreshes; totals are never combined across currencies. Quick-add uses `Link`/`widgetURL` deep links (`mywallet://`) rather than an `AppIntent` performed in place: adding a record needs an amount and a category, so the widget hands off to the app instead of writing anything itself. The extension is iOS-only — macOS App Groups require a team-prefixed identifier — so the macOS app build simply skips it.

**Provisioning:** the `group.com.app.My-Wallet` App Group must be enabled for the team's app ID and the widget's `com.app.My-Wallet.WalletWidgets` ID before a signed device build will install.

---

### 3.3 Biometric / Passcode Lock

> **Status:** Implemented locally; on-device biometric verification pending
> **Modules:** `WalletDomain` (new `Security/`), `WalletFeature` (new `Security/`), App entry point

Protect sensitive financial data with Face ID, Touch ID, or a custom passcode.

- [x] App lock toggle in Settings
- [x] Face ID / Touch ID authentication via `LocalAuthentication`
- [x] Fallback passcode (4-digit or 6-digit)
- [x] Auto-lock on app background or after timeout
- [x] Grace period setting (immediately, after 1 min, after 5 min)

Implementation notes (2026-09-10): The passcode is never stored. `PasscodeHasher` derives a SHA-256 verifier over a fresh 32-byte random salt, and `KeychainPasscodeStore` keeps only that verifier, as a `WhenUnlockedThisDeviceOnly` generic password so it neither syncs nor survives into a backup. Comparison is constant-time. A 4- or 6-digit passcode has a small keyspace, so the real protection is that keychain accessibility plus throttling: after five free attempts `AppLockPolicy` backs off 30s, 60s, 120s… capped at 15 minutes, and while throttled even the correct passcode is refused.

`AppLockPolicy` is pure and holds every decision: a fresh launch always locks, a returning app locks once the grace period elapses, and a clock that moved backwards is treated as expired so changing the device clock cannot extend a session. `AppLockGate` wraps the tabs and renders the lock screen instead of them — the content is not merely covered — and treats `.inactive` as backgrounding so the app-switcher snapshot cannot expose balances. Biometrics are offered on appearance with the keypad always available; a cancelled or failed prompt is not counted as a passcode attempt. Turning the lock off requires the current passcode.

`BiometricAuthenticating` and `PasscodeStoring` are protocols so the view model is tested against in-memory doubles rather than the keychain or `LocalAuthentication`. `NSFaceIDUsageDescription` is set; without it the Face ID prompt terminates the app.

---

### 3.4 Data Export / Import

> **Status:** Implemented locally; document-picker and share-sheet device verification pending
> **Modules:** `WalletDomain` (new `DataExchange/`), `WalletFeature` (new `DataExchange/`), `WalletFeature/Settings`

Let users export their data for backup or migration, and import from external sources.

- [x] Export all records as CSV with headers (date, type, amount, category, account, tags, note, payee)
- [x] Export as JSON for full fidelity (accounts, categories, tags, records)
- [x] Import from CSV with column mapping
- [x] Import preview and conflict resolution (duplicate detection)
- [x] Export/import from Settings screen

Implementation notes (2026-09-10): `CSV` implements RFC 4180 by hand rather than taking a dependency, because the rules worth guaranteeing are narrow: values holding commas, quotes or newlines must survive a round trip, and an export must re-import unchanged. Two bugs surfaced only because the round trip is tested — Swift treats `\r\n` as a single grapheme cluster, so matching on `"\r"` never fired for CRLF files, and `PaymentType`'s camelCase raw values silently lost their type when compared after `lowercased()`.

Export writes amounts as exact decimal strings, never doubles, and keeps the sign in the Type column as the ledger does. Labels are semicolon-separated so a comma never needs escaping inside the field, and the CSV carries a UTF-8 BOM so Excel opens accented names correctly. JSON is a versioned `WalletArchive` keeping identifiers intact; a file written by a newer format is refused rather than half-read. Neither format includes receipt images.

Import is planned before anything is written. Columns are matched by header name, ignoring case, order and extra columns, so only Date, Type, Amount and Account are actually required; amounts accept either decimal separator and stray currency symbols, and dates accept ISO plus common spreadsheet renderings. Rows resolve against existing accounts, categories (by full path or unambiguous name) and labels; unmatched labels are listed for creation. Every row lands in exactly one bucket — importable, duplicate, or problem — so the preview counts always add up. A duplicate is an existing record sharing account, kind, amount and timestamp to the second, which catches re-importing the same export and repeated rows inside one file. Errors name the spreadsheet row number. Rows are saved one at a time through `RecordUseCases`, so a row the domain rejects is reported without discarding those already written.

---

### 3.5 Onboarding Flow

> **Status:** Implemented locally; welcome step verified on simulator, later steps device-verification pending
> **Modules:** `WalletFeature` (new `Onboarding/`), App entry point

Guide new users through initial setup to reduce friction.

- [x] Welcome screen with app value proposition
- [x] Create first account step
- [x] Review starter categories step
- [x] Optional: set up a monthly budget
- [x] Skip option for experienced users
- [x] Show only on first launch (persisted flag)

Implementation notes (2026-09-10): Onboarding renders in place of the tabs rather than as a cover or sheet, which keeps it identical on iOS and macOS and guarantees the tabs are never briefly visible behind it. It sits inside `AppLockGate`, so a locked wallet still locks first. Completion is a local preference and deliberately not synced — it records that this device has been set up, not something about the wallet.

The account step writes through `AccountsViewModel`, so it gets the same validation as the account editor; a rejected save keeps the step and the draft rather than advancing. Because the account exists once that step passes, Back stops at the categories overview instead of offering to create it again. The categories step is read-only reassurance that the 60 starter categories are already there. The budget step is off by default and validated only when chosen — a zero limit is refused. Skip finishes immediately and keeps any account already created.

---

### 3.6 Multi-Currency Support

> **Modules:** `WalletDomain`, `WalletFeature/Shared`

Enhanced multi-currency handling beyond the current per-account currency.

- [ ] Primary/home currency setting
- [ ] Automatic exchange rate fetching (ECB, Open Exchange Rates, or similar free API)
- [ ] Converted totals in the dashboard using the home currency
- [ ] Historical exchange rates for accurate past-record conversion
- [ ] Manual rate override per record
- [ ] Currency gain/loss tracking for transfers

---

## Phase 4 — Platform & Ecosystem

Broader platform integration and ecosystem features.

---

### 4.1 Siri Shortcuts / App Intents

> **Modules:** New `AppIntents` integration

Voice-driven and automation-friendly record creation.

- [ ] "Add expense" intent with amount, category, account parameters
- [ ] "Show balance" intent for a specific account
- [ ] "Monthly summary" intent
- [ ] Spotlight indexing for accounts and categories
- [ ] Shortcuts app integration for custom automations

---

### 4.2 Apple Watch Companion

> **Modules:** New watchOS target, shared domain

Quick record entry and balance checking from the wrist.

- [ ] Complication showing total or account balance
- [ ] Quick expense entry with recent categories
- [ ] Today's spending summary
- [ ] Sync via WatchConnectivity or shared CloudKit

---

### 4.3 iPad Optimizations

> **Modules:** `WalletFeature` (adaptive layouts)

Take advantage of larger screens with richer layouts.

- [ ] Sidebar navigation with split view
- [ ] Dashboard and statistics side-by-side
- [ ] Keyboard shortcuts for common actions
- [ ] Drag-and-drop for record categorization
- [ ] Multi-window support with independent state

---

### 4.4 Notifications & Insights

> **Modules:** `WalletDomain` (new `Insights/`), push notification infrastructure

Proactive financial awareness through smart alerts.

- [ ] Weekly spending summary notification
- [ ] Unusual spending alerts (above average for a category)
- [ ] Streak tracking (days of logging, days under budget)
- [ ] Monthly comparison (spent more/less than last month)
- [ ] Configurable notification preferences in Settings

---

### 4.5 Camera Receipt Capture

> **Modules:** `WalletFeature/Records` (extend photo handling)

Capture receipts directly from the camera and optionally extract data.

- [ ] Camera capture integration (beyond current photo library)
- [ ] Multi-page receipt scanning with VisionKit
- [ ] Optional OCR for amount and date extraction (on-device via Vision)
- [ ] Store receipt images alongside records
- [ ] Receipt gallery view per record

---

## Phase 5 — Advanced & Long-Term

Features for power users and long-term product differentiation.

---

### 5.1 Debt Tracking

> **Modules:** `WalletDomain` (new `Debts/`), `WalletData`, `WalletFeature` (new `Debts/`)

Track money owed to or by other people.

- [ ] `Debt` entity: person, amount, direction (owe/owed), due date, linked records
- [ ] Debt list with net balance per person
- [ ] Settle debt — auto-create a transfer or expense record
- [ ] Reminders for outstanding debts
- [ ] History of partial payments

---

### 5.2 Savings Goals

> **Modules:** `WalletDomain` (new `Goals/`), `WalletData`, `WalletFeature` (new `Goals/`)

Set and track progress toward specific financial goals.

- [ ] `SavingsGoal` entity: name, target amount, deadline, linked account
- [ ] Visual progress indicator (bar or ring)
- [ ] Contribution history
- [ ] Projected completion date based on contribution rate
- [ ] Goal achieved celebration animation

---

### 5.3 Shared Wallets / Expense Splitting

> **Modules:** `WalletDomain` (extend), CloudKit sharing

Collaborative expense tracking for households or trips.

- [ ] Share a wallet/account with another iCloud user via `CKShare`
- [ ] Split an expense equally or by custom amounts
- [ ] Track who paid and who owes
- [ ] Settlement suggestions
- [ ] Shared budget tracking

---

### 5.4 Custom Dashboard

> **Modules:** `WalletFeature` (new `Dashboard/`)

A configurable home screen that surfaces the most relevant information.

- [ ] Drag-and-drop widget arrangement
- [ ] Customizable cards: balance, recent records, budget progress, spending chart, goals
- [ ] Quick-action buttons (add expense, add income, add transfer)
- [ ] Per-account or aggregate views
- [ ] Time period selector (today, this week, this month)

---

### 5.5 Theming & Customization

> **Modules:** `WalletFeature/Settings`, design system

Go beyond light/dark with richer visual personalization.

- [ ] Accent color picker (beyond system default)
- [ ] App icon variants
- [ ] Custom category icon selection (SF Symbols browser or custom images)
- [ ] Compact vs. comfortable list density setting
- [ ] Font size preference (independent of system Dynamic Type)

---

## Dependency Graph

Features should generally be implemented in phase order. Key cross-phase dependencies:

```
Record Editing (1.1) ──► Recurring Transactions (2.2)
Record Deletion (1.2) ──► Account Deletion (1.3)
Statistics Dashboard (1.5) ──► Budgets (2.1)
Statistics Dashboard (1.5) ──► Financial Reports (2.3)
Statistics Dashboard (1.5) ──► Home Screen Widgets (3.2)
Statistics Dashboard (1.5) ──► Custom Dashboard (5.4)
Budgets (2.1) ──► Notifications & Insights (4.4)
Multi-Currency Support (3.6) ──► Statistics Dashboard (1.5) [enhanced]
Data Export (3.4) ──► Financial Reports (2.3) [PDF reuse]
Biometric Lock (3.3) ──► Shared Wallets (5.3)
```

---

## Contributing

When picking up a feature:

1. Create a branch named `feature/<short-name>` (e.g. `feature/record-editing`).
2. Follow the module boundaries in [ARCHITECTURE.md](ARCHITECTURE.md) — domain first, then data, then feature.
3. Add or extend unit tests per [TESTING.md](TESTING.md).
4. Update [README.md](README.md) Feature Status on completion.
5. Update [DESIGN-SYSTEM.md](DESIGN-SYSTEM.md) if new visual components are introduced.
