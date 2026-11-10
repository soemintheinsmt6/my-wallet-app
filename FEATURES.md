# Feature Implementation Roadmap

Future features planned for **My Wallet**, grouped by priority phase. Each feature includes its scope, the modules it touches, and any dependencies on other features or infrastructure.

---

## Phase 1 — Core Gaps

These features close the gaps listed in the current Feature Status table and are prerequisites for a complete v1.0.

---

### 1.1 Record Editing

> **Status:** Implemented; verified on device
> **Modules:** `WalletDomain/Records`, `WalletData`, `WalletFeature/Records`

Allow users to open a saved record, modify any field (amount, category, account, date, tags, note, payee, payment type, photo) and save the changes. Balance adjustments must be recalculated atomically: reverse the old record's effect, apply the new values. Changing the account or switching between expense/income/transfer must handle the debit/credit swap correctly.

- [x] Add `updateRecord` to `RecordRepository` and `RecordUseCases`
- [x] Reuse `RecordEditorView` in edit mode, pre-populated from the existing `WalletRecord`
- [x] Atomic balance recalculation on account changes
- [x] Validate that photo replacement and removal work correctly
- [x] Unit tests for balance adjustment edge cases

---

### 1.2 Record Deletion

> **Status:** Implemented; verified on device
> **Modules:** `WalletDomain/Records`, `WalletData`, `WalletFeature/Records`

Delete a single record with confirmation. Reverse its balance effect on the associated account(s). Support swipe-to-delete and context-menu delete from the records list, plus a delete button in the detail view.

- [x] Add `deleteRecord` to `RecordRepository` and `RecordUseCases`
- [x] Confirmation alert before deletion
- [x] Balance reversal logic (expense adds back, income subtracts, transfer reverses both sides)
- [x] Remove associated photo data from storage
- [x] Unit tests for deletion and balance reversal

---

### 1.3 Account Deletion

> **Status:** Implemented; verified on device
> **Modules:** `WalletDomain/Accounts`, `WalletData`, `WalletFeature/Accounts`

Delete an account with full disclosure of the consequences. Show the number of records that will be orphaned or deleted. Offer two strategies: delete all associated records, or keep records as archived/unlinked entries. Transfers involving the deleted account need explicit handling.

- [x] Add `deleteAccount` to `AccountRepository` and `AccountUseCases`
- [x] Impact summary before confirmation (record count, balance)
- [x] Cascade or archive strategy selection
- [x] Handle transfer records referencing the deleted account
- [x] Unit tests for cascade and archive paths

---

### 1.7 Account Numbers

> **Status:** Implemented; not yet run in the app; CloudKit production schema deploy pending
> **Modules:** `WalletDomain/Accounts`, `WalletData`, `WalletFeature/Accounts`

Keep the number that identifies an account at its bank, card issuer, broker or lender, so accounts with similar names can be told apart and the number is at hand when it is needed.

- [x] Optional number for every type but Cash, titled by type: Card Number, Loan Number, otherwise Account Number
- [x] Letters, digits, spaces and dashes, up to 34 characters (IBAN length)
- [x] Stored whole and synced with the account; shown as `•••• 1234` in the Accounts list and on the account screen
- [x] Copying the full number from the account screen
- [x] Included in JSON backups; older backups without it still open

Implementation notes (2026-11-03): The number is kept whole rather than as its last four digits so it can be copied when paying or quoting it, but the full value appears only in the editor; everywhere else it is masked to its last four letters or digits, skipping separators. Copying uses a clipboard entry that stays on the device (no Universal Clipboard) and expires after a minute on iOS; macOS offers neither option, so it is an ordinary copy there. Switching an account to Cash clears its number when saved, so no hidden number is left behind. It travels with the account through iCloud and into the JSON backup, the user's own copy of their data, but not into the widget snapshot, the Apple Watch or Shortcuts. The stored field is a defaulted string, a lightweight CloudKit-compatible addition like the account icon, marked `.allowsCloudEncryption`: CloudKit encrypts it with keys from the user's iCloud Keychain, so the synced copy is end-to-end encrypted even without Advanced Data Protection. CloudKit cannot change a field's encryption once it is in the production schema, so the option ships with the field's first deploy and a test keeps it there. The cost is that a reset iCloud Keychain leaves the synced value unreadable; numbers already on devices stay. On the device the number is a plain field in the app's store, protected by the system's default file protection, and the JSON backup holds it in plain text.

---

### 1.4 Category Deletion

> **Status:** Implemented; verified on device, iCloud sync included
> **Modules:** `WalletDomain/Categories`, `WalletData`, `WalletFeature/Categories`

Delete a root category or subcategory. Deleting a root category should offer to reassign its subcategories or delete them. Records using a deleted category/subcategory should fall back to an "Uncategorized" state rather than losing data.

- [x] Add `deleteCategory` to `CategoryRepository` and `CategoryUseCases`
- [x] Reassign-or-delete prompt for subcategories under a deleted parent
- [x] Graceful fallback for records referencing deleted categories
- [x] Prevent deletion of the last remaining category
- [x] Unit tests for reassignment and orphaned-record handling

---

### 1.5 Statistics Dashboard

> **Status:** Implemented; verified on device
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

### 1.6 Balance Adjustments

> **Status:** Implemented; unit-tested and built, not yet verified on device
> **Modules:** `WalletDomain/Records`, `WalletData`, `WalletFeature/Accounts`, `WalletFeature/Records`

An account's balance changes for reasons the user did not enter as income or an expense, such as bank interest, a fee, or a difference found against a statement. **Adjust Balance** on an account's screen records the change as its own entry, so the balance's history explains every change instead of the number being overwritten.

- [x] Increase or decrease by an amount, with a date, note, label and photo, and a preview of the balance once saved
- [x] Recorded in the ledger and listed with the account's records as "Balance adjustment", with the note beside the account name
- [x] Editing or deleting an adjustment reverses its effect like any other record
- [x] Left out of income, expense, budget, insight, widget and day totals, like transfers; balance history and statements include it
- [x] CSV export and import as `adjustment increase` / `adjustment decrease`; backups keep the flag
- [x] Unit tests for balances, edit/delete reversal, validation, totals, older drafts decoding and CSV round-tripping

An adjustment is an ordinary record with an `isAdjustment` flag: an increase is stored with the income kind and a decrease with the expense kind. Balance arithmetic therefore needs no new case, and an older build that sees a synced adjustment reads it as income or an expense of the same amount, so balances still agree across devices. The flag is a defaulted attribute, a lightweight CloudKit-compatible addition that is **unverified against a deployed CloudKit schema**. Adjustments need no category and offer no payee, payment type, split or repeat, since they correct a balance rather than pay someone. Interest that should count as income in statistics can still be entered as an Income record under a category instead.

Changing the balance in the account editor is recorded the same way: the difference from today's balance is saved as an adjustment dated now, with the note "Balance edited", in the same save as the account's other edits. The opening balance is therefore set only when the account is created, and earlier history never shifts. Before 2026-11-02, editing the balance rewrote the opening balance instead, so corrections made then still apply retrospectively.

---

Implementation notes (2026-09-06): Phase 1 is implemented. Statistics keeps currencies separate; automatic conversion remains Phase 3.6. Balance history is reconstructed from current base balances and the ledger, so manual balance corrections apply retrospectively. Category deletion adds an optional `deletionDate` tombstone to preserve deleted starter IDs across reseeding. Archived account records retain currency snapshots and surviving transfer legs; editing an unlinked record requires selecting valid accounts again. Phase 2 is implemented below; Phases 3–5 remain planned.

## Phase 2 — Financial Intelligence

Features that help users understand and control their finances beyond basic tracking.

---

### 2.1 Budgets

> **Status:** Implemented; verified on device, notifications included
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

> **Status:** Implemented; verified on device, notifications included
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

> **Status:** Implemented; verified on device, PDF export included
> **Modules:** `WalletFeature` (new `Reports/`)

Generate downloadable or shareable reports summarizing financial activity.

- [x] Monthly/yearly summary report (income, expenses, net, top categories)
- [x] Category-level breakdown report
- [x] Account statement view with running balance
- [x] Export as PDF or share via system share sheet
- [x] Date range selection for custom reports

---

### 2.4 Bill Reminders

> **Status:** Implemented; verified on device, notifications included
> **Modules:** `WalletDomain` (new `Reminders/`), `WalletData`, `WalletFeature` (new `Reminders/`)

Track upcoming bills and due dates with push notification reminders.

- [x] `BillReminder` entity: name, amount, due date, recurrence, linked category/account
- [x] Local notification scheduling (1 day before, on due date, configurable)
- [x] Mark as paid — optionally auto-create a record
- [x] Overdue bill highlighting
- [x] Calendar view of upcoming bills

---

### 2.5 Cash-Flow Forecast

> **Status:** Implemented; unit-tested and built, not yet verified on device
> **Modules:** `WalletDomain` (new `Forecast/`), `WalletFeature/Home`, `WalletFeature/Planning`

See each account's balance over the next 30 days, moved by what is already planned for it, so a shortfall shows up before it happens rather than on a statement.

- [x] `CashFlowForecaster` projects each account from its recurring series and unpaid bills
- [x] Skipped, modified and already-generated occurrences honoured; paused and cancelled series ignored
- [x] A bill that a recurring expense already pays is counted once
- [x] Warning when an account is forecast to fall below zero, or below its minimum when one is set
- [x] Cash Flow Forecast Dashboard card, with a detail sheet charting the daily balance and listing every planned item
- [ ] Notification ahead of a forecast shortfall

Implementation notes (2026-11-04): the forecast only moves a balance by what the person has scheduled — recurring series and unpaid bills — and never guesses from past spending, so every figure traces back to something they can open in Planning and change. Nothing new is stored; it is worked out from the accounts' balances and the planning data whenever the Dashboard draws, which is cheap since a wallet holds few series and bills.

Each active series contributes the occurrences the generator would write within the horizon, from its next index: a skipped or already-generated occurrence contributes nothing, and a modified one lands on its own date and amount whatever its index, as generation treats it. Paused and cancelled series contribute nothing. A transfer moves both accounts, through the same `balanceEffects` the stored balances use. Each unpaid bill contributes every due date in the horizon as an expense on its account, since paying it with Add Expense records exactly that. An occurrence or bill already due has not reached the balance yet, so it lands today and is marked overdue.

A bill is often only a reminder for a payment a recurring series already records (rent, a subscription). When a bill falls within three days (`LedgerMatcher.postingLagDays`) of a recurring expense of the same amount on the same account, only the recurring one is counted; otherwise the payment would be taken twice. A bill reminding of a payment with a different amount, or on another account, is still counted.

Warnings depend on the account. Cash, checking, savings and other accounts warn when the balance would fall below zero; credit cards, loans and investments routinely sit below zero or swing, so they warn only when the person has turned on a minimum-balance alert for them, and then below that minimum. Any account with a minimum alert warns below its minimum. The card lists accounts forecast to fall below their threshold first, soonest first, and shows when and how low ("Falls to −$30 on 19 Nov"); other accounts show their lowest point and where they end in 30 days. The detail sheet reuses the Balance Trend chart for the day-by-day balance and lists each planned item with the balance it leaves.

Limitations: income or spending that is not scheduled (most day-to-day purchases) is not forecast, so the figure is what the plan alone does to the balance; a bill in another currency than its account is taken at its own amount, as paying it does; and the notification ahead of a shortfall is not built yet.

Implementation notes (2026-09-06): Phase 2 adds a Planning tab for budgets, recurring series, bills and reports. Monthly/weekly budgets are anchored to their start date, use included accounts in one currency, and roll over only positive unused funds. Recurring records are generated on launch/foreground or manual refresh in batches of up to 500 per series; later records do not block behind postponed individual occurrences. Occurrence receipts prevent local retries or record deletion from regenerating charges. Notification permission is explicitly requested from the budget/bill editor; the nearest 60 eligible notices are scheduled/refreshed on app activity. Reports include native paginated PDF export and currency-separated summaries. Four additive SwiftData models store Codable payloads; signed-device CloudKit and notification delivery still require verification.

## Phase 3 — User Experience Enhancements

Polish and convenience features that make daily use smoother.

---

### 3.1 Search and Filtering

> **Status:** Implemented; verified on device
> **Modules:** `WalletDomain/Records`, `WalletFeature/Records`

Full-text search across records with advanced filtering.

- [x] Search by note, payee, amount, category name, tag name
- [x] Filter by date range, record type, account, category, tag, payment type
- [x] Combine search with filters
- [x] Recent searches history
- [x] Results sorted by relevance or date

Implementation notes (2026-09-10): `RecordSearch` is a pure domain calculation over the records already loaded by `RecordsViewModel`; there is no new persistence or repository contract. Every whitespace-separated term must match at least one of payee, note, category name (including its parent), label name or amount, compared case- and diacritic-insensitively. Filter groups intersect while values inside a group union; selecting a root category includes its subcategories and excludes uncategorized records, and an account filter matches either leg of a transfer. Date ranges are start-inclusive/end-exclusive and amount bounds are inclusive, comparing the record's own amount without currency conversion. Relevance falls back to newest-first without search text, and all orders break ties deterministically. Since 2026-11-03 search results also get day headers: the list groups ranked results by day, newest day first, keeping the best match first within each day, so relevance decides order inside a day rather than across the whole list. Recent searches are a capped, newline-separated local preference cleared by Reset Wallet Data; they do not sync.

---

### 3.2 Home Screen Widgets

> **Status:** Implemented; widget rendering verified on device
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

> **Status:** Implemented; Face ID/Touch ID and passcode verified on device
> **Modules:** `WalletDomain` (new `Security/`), `WalletFeature` (new `Security/`), App entry point

Protect sensitive financial data with Face ID, Touch ID, or a custom passcode.

- [x] App lock toggle in Settings
- [x] Face ID / Touch ID authentication via `LocalAuthentication`
- [x] Biometrics as the whole lock, with no wallet passcode behind them
- [x] Fallback passcode (4-digit or 6-digit)
- [x] Auto-lock on app background or after timeout
- [x] Grace period setting (immediately, after 1 min, after 5 min)

Implementation notes (2026-09-10): The passcode is never stored. `PasscodeHasher` derives a SHA-256 verifier over a fresh 32-byte random salt, and `KeychainPasscodeStore` keeps only that verifier, as a `WhenUnlockedThisDeviceOnly` generic password so it neither syncs nor survives into a backup. Comparison is constant-time. A 4- or 6-digit passcode has a small keyspace, so the real protection is that keychain accessibility plus throttling: after five free attempts `AppLockPolicy` backs off 30s, 60s, 120s… capped at 15 minutes, and while throttled even the correct passcode is refused.

`AppLockPolicy` is pure and holds every decision: a fresh launch always locks, a returning app locks once the grace period elapses, and a clock that moved backwards is treated as expired so changing the device clock cannot extend a session. `AppLockGate` wraps the tabs and renders the lock screen instead of them — the content is not merely covered — and treats `.inactive` as backgrounding so the app-switcher snapshot cannot expose balances. Biometrics are offered on appearance with the keypad always available; a cancelled or failed prompt is not counted as a passcode attempt. Turning the lock off requires the current passcode.

`BiometricAuthenticating` and `PasscodeStoring` are protocols so the view model is tested against in-memory doubles rather than the keychain or `LocalAuthentication`. `NSFaceIDUsageDescription` is set; without it the Face ID prompt terminates the app.

Update (2026-09-11): biometrics can now hold the lock on their own. With no wallet passcode set, `isBiometricOnly` evaluates `.deviceOwnerAuthentication` rather than `.deviceOwnerAuthenticationWithBiometrics`, so the device passcode answers when a face or finger will not and the wallet cannot be sealed behind a prompt nothing satisfies; enabling it is refused outright on a device that can verify nobody, and both enabling and disabling require passing that same check. Setting a wallet passcode supersedes the biometric-only lock. Two fixes came with it: the system prompt resigns active, and the return to active that follows a successful unlock was being read as coming back from the background, which put the lock screen straight back up — `applicationDidBecomeActive` now locks only when it has a timestamp from an actual absence. Enrollment is also re-read on activation instead of trusted from launch.

---

### 3.4 Data Export / Import

> **Status:** Implemented; document picker and share sheet verified on device
> **Modules:** `WalletDomain` (new `DataExchange/`), `WalletFeature` (new `DataExchange/`), `WalletFeature/Settings`

Let users export their data for backup or migration, and import from external sources.

- [x] Export all records as CSV with headers (date, type, amount, category, account, tags, note, payee)
- [x] Export as JSON for full fidelity (accounts, categories, tags, records)
- [x] Import from CSV with column mapping
- [x] Import preview and conflict resolution (duplicate detection)
- [x] Export/import from Settings screen
- [x] Import bank statement exports (aliased headers, signed or Debit/Credit amounts, chosen account and fallback categories)
- [x] Categorise rows by payee from past records, in the import and the record editor

Implementation notes (2026-09-10): `CSV` implements RFC 4180 by hand rather than taking a dependency, because the rules worth guaranteeing are narrow: values holding commas, quotes or newlines must survive a round trip, and an export must re-import unchanged. Two bugs surfaced only because the round trip is tested — Swift treats `\r\n` as a single grapheme cluster, so matching on `"\r"` never fired for CRLF files, and `PaymentType`'s camelCase raw values silently lost their type when compared after `lowercased()`.

Export writes amounts as exact decimal strings, never doubles, and keeps the sign in the Type column as the ledger does. Labels are semicolon-separated so a comma never needs escaping inside the field, and the CSV carries a UTF-8 BOM so Excel opens accented names correctly. JSON is a versioned `WalletArchive` keeping identifiers intact; a file written by a newer format is refused rather than half-read. Neither format includes receipt images.

Import is planned before anything is written. Columns are matched by header name, ignoring case, order and extra columns, so only Date, Type, Amount and Account are actually required; amounts accept either decimal separator and stray currency symbols, and dates accept ISO plus common spreadsheet renderings. Rows resolve against existing accounts, categories (by full path or unambiguous name) and labels; unmatched labels are listed for creation. Every row lands in exactly one bucket — importable, duplicate, or problem — so the preview counts always add up. A duplicate is an existing record sharing account, kind, amount and timestamp to the second, which catches re-importing the same export and repeated rows inside one file. Errors name the spreadsheet row number. Rows are saved one at a time through `RecordUseCases`, so a row the domain rejects is reported without discarding those already written.

Bank statements (2026-11-03): a bank's export is the realistic way to bring real transactions in without a bank connection, but it names columns its own way, has no Account or Category column, and gives direction by sign or by separate Debit/Credit columns. Headers now also match common bank names ("Posting Date", "Description", "Money Out"…), and the app's own names win when both appear. Type is optional. A row's direction comes from Type when it names an app type (expense, income, transfer, adjustment) or a bank one (debit, credit); otherwise a Debit value or a negative Amount is an expense and a Credit value or a positive Amount is income. A bank's own Type values such as "Sale" are allowed only in files that carry signs, so a typo in the app's own CSV is still reported. "Amounts are spending" flips the sign for card statements that list purchases as positive. When the file has no Account column the person chooses an account first. Income and expense rows need a category, so rows the file does not categorise take a fallback chosen per kind in the review (income starts in the starter Income category) and are listed under "Cannot import" until one is chosen. Previously such rows passed the preview and then failed at save. Dates are read day-first for a whole file when any date's first part is over 12, and dotted, `15 Jan 2026` and two-digit-year forms are accepted. Accounting negatives (`(12.34)`, `12.34-`) parse. Bank rows have no time of day, so two identical purchases on one day are real: date-only rows are matched one-for-one against existing records rather than flagged as repeats within the file, and re-importing a statement still matches every row. Debit and Credit are import-only; exports are unchanged.

Matching manual entries (2026-11-03): a statement usually overlaps records typed in by hand, which have a time of day and are often dated before the bank posts them. `LedgerMatcher` matches each date-only row to a record moving the same amount the same way through the same account, dated the same day or up to three days earlier (never later, since a bank does not post before the purchase). A transfer counts as money out of its source and money in to its destination at its received amount, so one entered by hand matches both accounts' statements. Matching stays one-for-one; same-day matches are settled for every row before any lagged one, so a row with an exact match is never beaten to it; within the lag the closest earlier record wins. The review lists matched rows with the date of the record each matched, and Import Anyway overrides a wrong match (for example a second identical purchase that was never entered), freeing that record for another row. Rows with a time, as in the app's own export, keep exact-second matching.

Near amounts (2026-11-03): a card charge in another currency, a foreign-transaction fee or a rounded entry settles slightly off what was typed, so amounts within 5% of the bank's amount also match. Matches are settled in three rounds, each run for every row before the next: exact amount the same day, exact amount within the lag, then a near amount within the lag (closest day, then closest amount). So an exact match always beats a near one, and one row's near match never takes the record another row matches exactly. The review shows the amount that was entered when it differs. Tips (15–20%) are deliberately outside the tolerance, since a band that wide would match unrelated purchases; Import Anyway still covers a wrong near match. Records are indexed by account, direction and day, so a row reads only the records in its few-day window rather than every record in the account.

Tips and updating to the bank's amount (2026-11-03): a tip is added after a bill is entered, so an expense the bank charged up to 25% more for now matches too. That band would catch unrelated purchases on its own, so it is the last round, it runs only against records no other row matched (a bill whose own bank row is in the statement is taken by that row first), and it applies only to expense bills, never to income, transfers or balance adjustments. Skipping a matched row while leaving the record as entered would leave the balance short by the tip or fee. So by default the import changes the matched record's amount to the bank's, keeping its category, payee, note, time, labels and photo. A toggle in the review turns this off for the whole import, and the review shows each change ("tip $10.00. Will change to $60.00"). A cross-currency transfer updates the side the statement shows (sent amount or received amount). A same-currency transfer keeps its single amount, since one bank's statement cannot change it without contradicting the other's. A split record keeps its amount because its shares must add up to it, and the result says so. A statement that is already fully entered can still be applied, to bring in only its tips and fees.

Categories by payee (2026-11-04): a statement names no categories, so every unmatched row took one fallback per kind and had to be refiled by hand. `PayeeCategorizer` now files a row under the category last used for its payee in the wallet's own records, and only rows from payees never seen before fall back. Nothing new is stored, so there is no schema or CloudKit change: the suggestions are learned from the ledger each time the records change, and so follow every edit and every synced device. Payees are compared ignoring case, accents, punctuation, words containing digits (store, terminal and reference numbers) and processor prefixes such as POS, VISA, SQ and PAYPAL, so "POS STARBUCKS #1234" is "Starbucks". A bank description that only starts with a known payee ("GRAB TRIP SINGAPORE" after "Grab") takes that payee's category, the longest known start winning, so "Grab Food" can be filed apart from "Grab". The most recent record wins over the most frequent, because re-filing a payee means habits changed. Income and spending are learned separately, transfers and adjustments teach nothing, and a deleted category is never suggested. The review shows each row's category beside its payee and has a toggle to use the fallbacks instead. The record editor uses the same suggestion: a new income or expense takes the learned category when a payee is entered, unless the person has already chosen a category, and editing a saved record never changes its category. A limitation: records imported earlier under a fallback category teach that fallback until one is refiled, and the newest refiled record then wins.

Payee suggestions (2026-11-04): learning by payee only works if a payee is spelled the same way each time, so the Payee screen now lists up to five past payees for the record's kind. With nothing typed it offers the most recent. As you type it matches the start of a payee or of any word in it, ignoring case and accents ("cof" finds "Blue Bottle Coffee"), listing payees the text starts first, then the most used, then the most recent, and leaving out one already typed in full. `PayeeSuggestions` groups spellings by the categorizer's key and offers each payee once under its most used spelling, so a hand-typed "Starbucks" stands for the bank's "STARBUCKS #0042" and "#0051". Because numbers are ignored, "Bus 36" and "Bus 52" are offered as one payee too. Each suggestion shows the category it would fill in when choosing it would fill one in. Like the categorizer, it stores nothing.

Payers and other kinds (2026-11-04): on the device check, income offered nothing, because most wallets record payees on spending and few on income. Payees of the record's own kind still come first, but payees recorded under other kinds now fill the remaining places, and a name recorded under two kinds is offered once. Income calls the field Payer (row, screen title and caption) since money comes from someone; expenses and transfers keep Payee. Both are stored as the same `payee` field, so nothing about storage, export or search changes.

Faster Payee screen (2026-11-04): opening Payee lagged as its list appeared, because the first use built the suggestions and the categories on the main thread as the screen slid in. Measured at 10,000 records with 300 distinct payees in a release build on a Mac, that cost 18 ms for suggestions and 17 ms for categories; a phone is slower. Both now work out each distinct payee text once instead of once per record, since payees repeat, which brings them to 1.5 ms and 2 ms. The record editor also starts building them in the background as soon as it opens, so by the time Payee is tapped they are ready, and a build that read the ledger before a later change is dropped rather than cached. Lookups while typing take under 0.1 ms.

---

### 3.5 Onboarding Flow

> **Status:** Implemented; every step verified on device
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

> **Status:** Implemented; live rate download and iCloud sync verified on device
> **Modules:** `WalletDomain` (new `Currency/`), `WalletData` (new `Remote/`), `WalletFeature` (new `Currency/`)

Enhanced multi-currency handling beyond the current per-account currency.

- [x] Main currency setting (one setting for new items, summaries and conversion)
- [x] Automatic exchange rate fetching (ECB via the keyless Frankfurter feed)
- [x] Converted totals in the dashboard using the main currency
- [x] Historical exchange rates available per day for past-record conversion
- [x] Manual rate override per record
- [x] Currency gain/loss tracking for transfers
- [x] Choice of counting large amounts in lakhs or millions

Update (2026-11-03): chart totals used to count lakhs for MMK, INR, PKR, BDT, NPR and LKR and millions (K, M, B) for everything else, so one wallet could show "52.7 lakhs" beside "5.3M". Settings → Currency → Count Large Amounts In now picks Automatic (the old behavior, and the default), Lakhs or Millions for every currency. It applies to the totals inside the Dashboard Expenses and Statistics donuts and to the amount axis of every Dashboard and Statistics chart ("50L" or "5M"); exact amounts in cards, legends and lists are unchanged. The compact figures in small widgets and watch complications follow it too ("MMK 52.7L" or "MMK 5.3M"): the choice rides in `WalletSnapshot`, since the extensions cannot read the app's preferences, and a change rewrites the snapshot so widgets and the watch update. Full-size widget amounts and the watch app keep exact figures.

Update (2026-11-03, main currency): the separate Home Currency (what converted totals are shown in) and Default Currency (where new items start) are now one Main Currency. The two were nearly always the same and the home currency did nothing unless converted totals were on, so two rows mostly confused. Existing choices carry over: someone with converted totals on keeps the currency those totals were shown in (their home currency, or the region's currency if they never picked one), anyone else keeps their default currency, and the old preference keys are then removed. What is lost is creating items in one currency while totals convert into another; changing a new account's currency covers that rare case.

The ECB feed publishes about 30 currencies and not MMK, PKR, BDT, NPR or LKR. With such a main currency, no rate download is attempted, converted totals stay off, and Settings says why instead of failing each refresh; a record's own pinned rate still converts. This was already true for those currencies' accounts before the merge, since the feed has no rate for them in either direction. `ExchangeRateProviding` gained an optional `supportedCurrencies`, which the Frankfurter provider fills from the feed's `/currencies` list (checked 2026-11-03; BGN has since left it).

Implementation notes (2026-09-10): Conversion is strictly additive. Accounts keep their own currency, per-currency totals stay exactly as they were, and converted figures are marked with `≈` as estimates — a single daily reference rate is not what a bank actually charged. Nothing converts until the user picks a home currency and turns on Show Converted Totals, and a combined total appears only when every currency in play can be converted; a missing rate yields no figure rather than a wrong one.

`CurrencyConverter` is pure and `Decimal` throughout, with no `Double` in the money path. Conversion crosses through the rate set's base, so a EUR-quoted feed still converts USD to GBP, and results round to the target currency's own precision — zero-decimal currencies like JPY never gain cents. Rates come from Frankfurter (ECB-backed, no API key), whose endpoint also answers any historical day, which is what accurate conversion of past records needs; JSON numbers are decoded from their text so no precision is lost before the `Decimal` arithmetic. The last set is cached on disk, refreshed at most every six hours, and a failed refresh keeps the cached rates and says which day they are from rather than dropping conversion.

The per-record pinned rate adds one optional `manualRateValue` string to `TransactionRecord`. Optional and defaulted, so it is a lightweight, CloudKit-compatible addition and existing records simply have no override. It is validated as positive, wins over the market rate, and works offline. Cross-currency transfers report the gain or loss between what left and what arrived, in the home currency. `CurrencyViewModel` reaches the record editor and detail through a SwiftUI environment value rather than being threaded through every screen that presents them.

**Outstanding:** the rate download has not been exercised against the live endpoint from this environment, and the added persisted field needs a signed-device CloudKit check before production, per the schema guidance in ARCHITECTURE.md.

---

## Phase 4 — Platform & Ecosystem

Broader platform integration and ecosystem features.

---

### 4.1 Siri Shortcuts / App Intents

> **Status:** Implemented; Siri and Shortcuts verified on device
> **Modules:** `My Wallet/App/Intents/` (AppIntents, CoreSpotlight)

Voice-driven and automation-friendly record creation.

- [x] "Add expense" intent with amount, category, account parameters
- [x] "Show balance" intent for a specific account
- [x] "Monthly summary" intent
- [x] Spotlight indexing for accounts and categories
- [x] Shortcuts app integration for custom automations

Implementation notes (2026-09-10): Intents live in the app target because `ExtractAppIntentsMetadata` runs per target. Add Expense writes through `RecordUseCases`, so a record created by Siri gets exactly the same validation and balance handling as one typed into the editor; with several accounts and none specified it asks rather than guessing, but falls back to the only account when there is just one. Accounts and categories are exposed as `AppEntity` types with queries, so Shortcuts shows real pickers instead of free text, and categories are listed by their full "Parent / Child" path.

Show Balance and Monthly Summary read the widget snapshot rather than opening the store, so they answer instantly without paying for a CloudKit-backed SwiftData container; only a named account's balance needs live data. All three run in the background without opening the app. `IntentWallet` caches the container per process because Shortcuts may run several intents in a row.

Spotlight indexes names and types only — never balances or record details — because Spotlight results are visible on a locked device and the app deliberately hides figures behind its own lock. Indexing replaces the whole domain so deletions disappear too, skips identical passes, reindexes on rename rather than only on count changes, and is cleared by Reset Wallet Data alongside the widget snapshot.

**Verification:** the built app's `Metadata.appintents` was inspected and contains all three actions, the `WalletShortcuts` provider and every Siri phrase template. The intents were not invoked from Siri or the Shortcuts app, and Spotlight results were not exercised on a device.

---

### 4.2 Apple Watch Companion

> **Status:** Implemented; **not compiled** — the watchOS platform is not installed in the build environment
> **Modules:** New `WalletWatch` and `WalletWatchWidgets` targets, `WalletDomain/Widgets/`, `My Wallet/App/Watch/`

Quick record entry and balance checking from the wrist.

- [x] Complication showing total or account balance
- [x] Quick expense entry with recent categories
- [x] Today's spending summary
- [x] Sync via WatchConnectivity

Implementation notes (2026-09-11): The store lives on the phone, so the watch never writes to the wallet. The phone mirrors a `WalletSnapshot` with `updateApplicationContext` — latest-state-wins, delivered in the background, which suits a summary far better than a queue of stale ones — and the watch proposes expenses with `transferUserInfo`, so a capture made out of range is queued and delivered later rather than failing. Incoming expenses are written through `RecordUseCases`, so a wrist capture is validated exactly like a typed record. `WalletWatchTransfer` holds the payload encoding once, shared by both processes, so the two sides cannot drift.

The snapshot gained accounts, most-used expense categories and today's spend so quick entry works without the store, and `WalletSnapshot` now decodes field by field: a snapshot written by an older build still loads instead of blanking every widget. The watch persists what it receives into the App Group so its complications — which cannot use WatchConnectivity themselves — have data after a relaunch out of range.

**Build status:** the watchOS platform (`watchOS 26.5`) is not installed here, only its SDK headers, so neither watch target could be compiled and neither could the iOS app while it embedded the watch app. To keep `xcodebuild -scheme 'My Wallet'` working, the iOS target's **Embed Watch Content** phase and its dependency on `WalletWatch` are currently detached — both targets exist and are fully configured, but the watch app is not embedded in the iOS app.

**To finish on a machine with the platform:** run `xcodebuild -downloadPlatform watchOS`, then in Xcode select the *My Wallet* target → General → **Embed Watch Content** and add `WalletWatch.app` (this restores the `A30000000000000000000034` copy-files phase and the `A30000000000000000000040` dependency). Then build `WalletWatch` and `WalletWatchWidgets`. Treat every line of watch code as unreviewed by a compiler until that happens.

---

### 4.3 iPad Optimizations

> **Status:** Implemented; verified on iPad and Mac
> **Modules:** `My Wallet/App/Navigation/`, `WalletFeature/Shared/Navigation/`, `WalletFeature/Records/`

Take advantage of larger screens with richer layouts.

- [x] Sidebar navigation with split view
- [x] Dashboard and statistics side-by-side
- [x] Keyboard shortcuts for common actions
- [x] Drag-and-drop for record categorization
- [x] Multi-window support with independent state

Implementation notes (2026-09-11): `WalletShellView` picks the layout from the horizontal size class — tabs when compact, `NavigationSplitView` when regular — and owns the selection and pending-add state so rotating an iPad or resizing a macOS window keeps the user where they were. macOS is always wide. Everything shell-level (deep links, Spotlight continuation, snapshot and watch startup, command handling) moved out of `WalletTabsView`, which is now just the compact layout. On iOS a `List` selection binding must be optional, so a cleared sidebar selection keeps the previous tab rather than emptying the detail.

Selecting Dashboard in the sidebar shows it and Statistics side by side, because on a wide screen the summary and its charts are read together rather than one after the other.

Commands go through `WalletCommandBus` rather than reaching into a window, since a scene's commands are built once while the windows acting on them come and go: ⌘N/⇧⌘N/⇧⌘T for a new expense, income or transfer, ⌘F to find records, and ⌘1–⌘5 for the five destinations. Each request is a counter, not a flag, so pressing ⌘N twice opens the editor twice.

Records are draggable onto a category to refile them. The payload is `RecordTransfer`, carrying only the record's identifier under the app's own exported type `com.app.My-Wallet.record` — not plain text, which any view would accept — and the drop side re-reads the live record and saves it through `RecordUseCases` rather than writing a copy of stale values. Transfers without a category are skipped, since a transfer is not filed under one.

Multi-window is enabled through `UIApplicationSupportsMultipleScenes`. The composition root stays shared across windows by design, while each window keeps its own selection and navigation state.

---

### 4.4 Notifications & Insights

> **Status:** Implemented; notification delivery verified on device
> **Modules:** `WalletDomain` (new `Insights/`), `WalletFeature` (new `Insights/`), `My Wallet/App/`

Proactive financial awareness through smart alerts.

- [x] Weekly spending summary notification
- [x] Unusual spending alerts (above average for a category)
- [x] Streak tracking (days of logging, days under budget)
- [x] Monthly comparison (spent more/less than last month)
- [x] Configurable notification preferences in Settings

Implementation notes (2026-09-11): `WalletInsightsCalculator` is pure and takes both a clock and a calendar, so week starts, month lengths and "today" can all be tested directly. A category is called unusual only against **its own** recent three-month average — rent and coffee are not comparable — and must clear both a 1.5× multiple and a minimum amount, so a coffee twice over is not reported. A percentage change is withheld entirely when there was no prior spending, because "up 100% from nothing" misleads. Transfers, income and accounts excluded from stats never count as spending, matching every other figure in the app. A logging streak that reaches yesterday still counts: the day is not over.

Every notice is off until switched on, and the settings footer says so. Unusual-spending notices are keyed by category and month, so a category alerts at most once a month.

**A defect this exposed:** `WalletNotificationClient.synchronize` cancelled every pending `wallet.`-prefixed notice that was not in the batch it was given. A second source of notices would therefore have silently cancelled all bill and budget alerts. The protocol now takes the identifier prefixes the caller owns, so each source replaces only its own and leaves the rest alone. Existing identifiers were deliberately left unchanged, so no already-delivered alert can fire a second time.

---

### 4.5 Camera Receipt Capture

> **Status:** Implemented; camera scanning and OCR verified on device
> **Modules:** `WalletDomain` (new `Receipts/`), `WalletData`, `WalletFeature` (new `Receipts/`)

Capture receipts directly from the camera and optionally extract data.

- [x] Camera capture integration (beyond current photo library)
- [x] Multi-page receipt scanning with VisionKit
- [x] Optional OCR for amount and date extraction (on-device via Vision)
- [x] Store receipt images alongside records
- [x] Receipt gallery view per record

Implementation notes (2026-09-11): Scanning uses VisionKit's `VNDocumentCameraViewController`, which already handles edge detection, perspective correction and multi-page capture, so no custom camera UI was built. Pages are downsampled to 2000 px and JPEG-encoded before storage, so a long receipt does not cost several megabytes a page.

Pages live in their own `ReceiptRecord` model rather than as an array on `TransactionRecord`, so fetching the ledger never pulls image bytes. All properties are defaulted, keeping the addition CloudKit-compatible, and the link is a plain `recordID` like the rest of the schema. Deleting a record deletes its pages in the same save, and Reset Wallet Data clears them too — both covered by tests, since orphaned image blobs would otherwise be invisible and permanent. External storage is cleared before deletion, as record photos already do. A record holds at most 12 pages, and an oversized or empty page rejects the whole batch rather than storing part of it.

OCR runs on-device through Vision and is always a **suggestion the user accepts**, never applied silently over what they typed — reading a crumpled receipt is a guess. The interpretation is a pure function over recognized lines, so its rules are tested without Vision: a line naming a total wins, subtotals/tax/change/tip are excluded, and otherwise the largest amount is taken, which is nearly always the total. Amounts must carry two decimals, keeping quantities and phone numbers out, and a future-dated match is rejected because a receipt cannot be for tomorrow.

**A bug the tests caught:** the amount pattern allowed only a space or comma as a group separator, so the European form `1.234,56` parsed as `234.56` — silently wrong by a factor of ten.

Receipt storage reaches the editor and detail through a SwiftUI environment value, as the currency model does. Scanning is offered only where `VNDocumentCameraViewController.isSupported`, so simulators and Macs show the existing pages without a scan button.

---

Implementation notes (2026-09-11): Phase 4 is implemented. 4.1, 4.3, 4.4 and 4.5 compile and are covered by tests; **4.2 has never been compiled**, because the watchOS platform is not installed in the build environment — see its section for the two steps to finish it. Three defects were found by the tests written alongside these features: a notification client that would have silently cancelled all bill and budget alerts once a second source existed, an OCR amount pattern that misread the European `1.234,56` as `234.56`, and a watch snapshot that would have failed to decode anything written by an older build. Two schema additions were made, both optional and defaulted so they stay CloudKit-compatible: `manualRateValue` on `TransactionRecord` (Phase 3.6) and the separate `ReceiptRecord` model. Neither has been checked against a deployed CloudKit schema.

## Phase 5 — Advanced & Long-Term

Features for power users and long-term product differentiation.

---

### 5.1 Debt Tracking

> **Status:** Implemented; verified on device, reminders included
> **Modules:** `WalletDomain` (new `Debts/`), `WalletData`, `WalletFeature` (new `Debts/`)

Track money owed to or by other people.

- [x] `Debt` entity: person, amount, direction (owe/owed), due date, linked records
- [x] Debt list with net balance per person
- [x] Settle debt — auto-create a transfer or expense record
- [x] Reminders for outstanding debts
- [x] History of partial payments

Implementation notes (2026-09-11): A debt is deliberately **not** an account. It is a claim, not money the user holds, so folding it into account balances would misstate the wallet. Debts are grouped per person and per currency and netted, so two debts in opposite directions cancel into one number that says plainly who owes whom; names are matched case-insensitively. Settled debts stay visible for their history but contribute zero and sort to the bottom.

Payments are separate rows, so a debt can be settled piece by piece, and a payment beyond what is still outstanding is refused — a debt can never be overpaid into a negative balance. Settling optionally writes a real ledger record: a debt owed to the user settles as income, one the user owes as an expense. The record is written **first**, so if it fails the payment is not recorded either and the two can never disagree. Only accounts in the debt's own currency are offered, so the record cannot misstate the amount. Deleting a debt deletes its payments, since a payment without its debt could never be shown; records already created are kept.

Reminders reuse the notification client under a `wallet.debt.` prefix, disjoint from planning and insight notices, and only fire while a debt is still outstanding.

Money moved now (2026-11-10): settling recorded income or an expense, which is right when the money was already recorded (a shared bill a friend owes part of) but wrong for a cash loan. Lending 300 left the balance untouched, then being repaid added 300 of "income", so the balance ended 300 too high and statistics counted a loan as earnings; borrowing failed the same way in reverse. A debt can now record the money changing hands when it is made: Money moved now, with an account in the debt's currency, writes a balance adjustment (out when lending, in when borrowing) dated when the debt was made. Adjustments move the balance but count in no income, expense, budget or statistics total. The debt keeps that record's ID (`openingRecordID`, optional in its JSON, so older debts decode without it and nothing in the schema changes), and while it is set settling records the return as an adjustment the other way, with no category; lending and being repaid leave the balance where it started. Editing the debt's person, direction or amount updates that adjustment's amount, direction and payee, keeping anything else added to it, including a photo; its account and date stay, and the debt's currency is locked once it exists. The debt is validated before the adjustment is written, and the adjustment is removed if the debt then fails to save. Debts made without the switch settle as before. Settling such a debt now requires a category, since income and expenses need one; the sheet previously offered None, which failed at save.

Clear loan records (2026-11-10): on the device check, money added by a borrowed debt looked like it came from nowhere, since the record read "Balance adjustment", and the debt's two records did not look related. Those records now read "Lent to Ana" or "Borrowed from Ana" and "Repaid by Ana" or "Repaid to Ana", with a two-person tile, wherever records are listed. Nothing new is stored: `DebtsViewModel` derives the titles from each debt's opening record and its payments' records whenever debts load (the dashboard loads them at launch) and hands them to `RecordsViewModel`. Only debts whose money moved are titled; other settlements are real income or expenses and keep their category. The switch now reads "Add to my balance now" (or "Take from my balance now" when lending), and its caption says to leave it off when the money is already in the balance. Each debt now opens its own screen, like a bill's: a large Settle button leads it, as Mark as Paid leads a bill's, then the debt's records and its payment history. Payments were stored but never shown anywhere, so the partial-payment history listed above can now be seen, and a mistaken payment swiped away; a record it added is kept, as deleting a debt keeps them.

---

### 5.2 Savings Goals

> **Status:** Implemented; verified on device
> **Modules:** `WalletDomain` (new `Goals/`), `WalletData`, `WalletFeature` (new `Goals/`)

Set and track progress toward specific financial goals.

- [x] `SavingsGoal` entity: name, target amount, deadline, linked account
- [x] Visual progress indicator (ring)
- [x] Contribution history
- [x] Projected completion date based on contribution rate
- [x] Goal achieved celebration animation

Implementation notes (2026-09-11): Progress comes from contributions the user records, **not** from an account balance. An account usually holds more than one goal's worth of money, and reading the balance would let ordinary spending silently undo progress. The linked account is reference only, and stated as such in the form. Contributions may be negative, so a withdrawal moves progress down honestly rather than being hidden.

The projection is a straight-line extrapolation from the average saved per day since the first contribution; it is withheld when nothing has been contributed, when the goal is already reached, or when the rate is so slow the answer would be noise rather than information. A deadline turns that projection into an on-track or behind-schedule reading, and an achieved goal is never behind whatever its deadline said. Every one of those figures is stated in words — the ring only reinforces it.

Contributing can optionally record a real transfer between two of the user's accounts, so the money movement lands in balances and statistics. The celebration plays once, when a goal is first reached, and holds still under Reduce Motion.

Update (2026-11-01): Each goal now has a visible Add Money row under its progress. Contributing used to be reachable only by swiping the row right, so a new goal looked like it had nothing to do. The goal editor also shows a Progress section, with the amount saved and the same Add Money button, once the goal has been saved.

---

### 5.3 Shared Wallets / Expense Splitting

> **Status:** Splitting implemented and verified on device. **`CKShare` is not implemented** — see the blocker below
> **Modules:** `WalletDomain` (new `Sharing/`), `WalletData`, `WalletFeature` (new `Sharing/`)

Collaborative expense tracking for households or trips.

- [ ] Share a wallet/account with another iCloud user via `CKShare` — **blocked, see below**
- [x] Split an expense equally or by custom amounts
- [x] Track who paid and who owes
- [x] Settlement suggestions
- [x] Shared budget tracking

Implementation notes (2026-09-11): A split divides a record between people, recording both what each person owes and what each actually paid, so "who paid and who owes" comes from one consistent picture. Equal division gives the remainder away one minor unit at a time — splitting 10 three ways is 3.34/3.33/3.33, never 3.33 each, which would quietly lose a cent — and respects zero-decimal currencies. Percentages round per share with the last participant absorbing the drift, so the parts always add back to the exact total. A split is refused unless both the shares and the payments sum to the record's amount.

Settlement suggestions net everyone across every split and then repeatedly match the largest creditor with the largest debtor. That is the standard greedy approach: it does not always find the theoretical minimum — that problem is NP-hard — but it never needs more than one payment per person beyond the first, and it is deterministic, so the list never reshuffles. Tests assert that applying every suggestion leaves all balances at zero.

Shared budget tracking means a bill you front for a group counts toward **your** budget only for your own share: `BudgetProgress.calculate` takes an owner-share map, so putting 90 on your card for three people charges 30 against your food budget rather than 90. Splits are removed with their record and by Reset Wallet Data.

**Blocker — `CKShare`:** the app stores everything in SwiftData backed by `NSPersistentCloudKitContainer`'s **private** database. Real sharing needs the shared database as well, `CKShare` creation, share-metadata acceptance and a sharing controller — and SwiftData does not expose the `NSPersistentCloudKitContainer` sharing APIs that this requires. Delivering it means either dropping to Core Data directly for the shared store or running a second, hand-written CloudKit sync path alongside SwiftData. Both are substantial architectural changes, and neither could be verified here: it needs two iCloud accounts on signed devices. Rather than ship a large, unverifiable sync implementation that touches user data, this item is left undone and the local splitting features — which is where the day-to-day value is — are complete.

---

### 5.4 Custom Dashboard

> **Status:** Implemented; verified on device, drag reordering included
> **Modules:** `WalletFeature/Home/`

A configurable home screen that surfaces the most relevant information.

- [x] Drag-and-drop card arrangement
- [x] Customizable cards: balance, accounts, balance trend, expenses by category or label, top expenses, recent records, budget progress, spending chart, goals
- [x] Quick-action buttons (add expense, add income, add transfer)
- [x] Account cards opening a per-account screen (balance, today/week/month/year activity, its records)

Implementation notes (2026-09-11): Order and visibility are stored **separately from the card list**, so a card added in a later release is appended to the user's arrangement rather than resetting it, and hiding a card keeps its position for when it comes back. A card with nothing to show — no budgets, no bills, no goals — stays out of the way rather than rendering an empty shell.

The arrangement is local and cosmetic, so it is stored as encoded JSON in preferences rather than added to the synced schema.

Update (2026-11-01): the dashboard no longer has its own period and account scope. It always shows the current month across every account included in statistics, so its figures never depend on a setting the user has forgotten. Narrower views moved to the screens that own them: Statistics gained a Day period alongside Week, Month, Year and Custom and keeps its account filter; Records keeps its account filter; and a new Accounts card shows every account's balance, each opening `AccountDetailView` with that account's income and expenses for today, the week, month or year and the records that touched it. Arrangements saved with the old scope still load, the scope ignored, and gain the Accounts card directly after Balance.

Update (2026-11-01, later): the Day period was removed from Statistics again. Its trend chart, grouped by day, drew a single bar, and a single day's spending is already answered by the Records list and the Dashboard. A custom range still covers one day when needed.

Update (2026-11-01, later still): the spending trend only offers groupings that give the period several bars — days for a week; days or weeks for a month; weeks or months for a year — and falls back to the period's preferred grouping when a kept choice no longer fits. Grouping a month by month had drawn a single bar. Balance history no longer follows that grouping: it was sampled at the same steps, so a month grouped by month had two points, a flat line and a jump. It is now sampled daily up to a quarter, weekly up to two years and monthly beyond, stops at the current day instead of running flat into days to come, and keeps the whole period on its axis so a month in progress reads as "so far".

Update (2026-11-01, summary): Reports, Statistics and the Dashboard now open in the user's default currency when an account holds it, falling back to the currency most accounts use. Reports had always opened in USD and Statistics in the alphabetically first currency. The Reports financial summary moved from two tiles and a Net row to the shared summary card, and like Statistics it gained spending per day so far and a comparison with the previous period (`PeriodComparison`). A period in progress is compared with the same stretch of the previous one, since setting ten days of this month against all of last month would always read as "less". A currency menu sits in the summary header when several currencies are in use.

Update (2026-11-01): three chart cards follow the month's summary, all in the Balance card's currency. **Balance Trend** plots the end-of-day balance over the last 30 days as one line over a light area, with today's balance above it; touch and drag reads any day. **Expenses** is a donut of this month's spending by top-level category or by label, the total in the hole and a legend giving every part's name, share and amount; past six parts the smallest fold into one gray "Other". Label totals split a record carrying several labels evenly between them, so both views add up to the same total. **Top Expenses** ranks the five largest categories as bars scaled to the largest. The category colors are the app's identity colors and do not meet colorblind-separation targets on their own, so every part and bar is always named and valued in text, never identified by color alone. Existing arrangements gain the three cards directly after the summary.

---

### 5.5 Theming & Customization

> **Status:** Implemented; verified on device, app icon switching included
> **Modules:** `WalletFeature` (new `Theming/`), `My Wallet/App/`

Go beyond light/dark with richer visual personalization.

- [x] Accent color picker (beyond system default)
- [x] App icon variants
- [x] Custom category icon selection (curated SF Symbols browser)
- [x] Compact vs. comfortable list density setting
- [x] Text size preference layered on system Dynamic Type

Implementation notes (2026-09-11): "Default" applies **no tint at all**, so it genuinely keeps the asset catalog's accent rather than hard-coding a blue that merely looks like it. Accent swatches are never the only signal — each carries its name and a checkmark, and is marked selected for VoiceOver.

Text size is deliberately a **relative nudge on top of** the system setting rather than a replacement. The roadmap asked for a preference "independent of system Dynamic Type", but overriding it outright would ignore an accessibility choice the user already made at the OS level; Standard therefore applies nothing and lets Dynamic Type through untouched.

Three alternate icons (Midnight, Forest, Sunset) are declared in `Info.plist`. Since 2026-11-02 they share the designed primary mark, two cards fanning out of a wallet pocket, recolored per theme; the primary icon also has dark and tinted variants and a macOS rounded-square set. Setting the icon already in use is skipped, since iOS would otherwise show a pointless alert. Category icon overrides are stored locally: the seeded symbols are presentation metadata keyed by stable IDs, and adding a synced field for a purely cosmetic choice would mean a schema change. Clearing an override returns the shipped icon rather than a blank tile. The symbol list is curated rather than the whole SF Symbols catalog, most of which means nothing in a wallet.

Update (2026-11-10): List Density was stored and passed to every screen but no row read it, so Compact and Comfortable looked identical; its tests checked only the stored value. List rows now take their vertical padding through `walletListRowPadding(_:)`, which adds the density's extra padding (none for Compact, 6 points above and below for Comfortable) to the row's own: records (including on the Dashboard), accounts and balance alerts, categories and subcategories, labels, budgets and budget progress, bills, debts, goals, recurring series and occurrences, splits, drinking days, insights, the cash-flow forecast, the Planning hub, More, and the bill and debt screens' value rows. Compact leaves every row exactly as it was. A test lays a row out under each setting and checks Comfortable is taller by that padding. Editors keep one spacing, since they are forms rather than lists.

Update (2026-11-03): category and subcategory icons now sync through iCloud. Keeping them local meant a choice made on one device never reached another, while account icons, part of the account, already synced, so the two behaved differently. The icon is now an optional `symbolName` on the category record, `nil` for the starter icon: an additive, CloudKit-compatible field, written with a fresh timestamp like a rename so it wins over older copies. Existing choices move over by themselves: the first time categories load, each icon saved in this device's preferences is copied onto its category, unless that category already has an icon synced from another device, and the local copy is then removed. Two devices with different local choices for the same category keep whichever is copied last. Backups now include the icon, and older backups without it still open. Reset Wallet Data now resets icons with the rest of the category edits. Deploy the CloudKit development schema to production before release, or production iCloud will not carry the field.

---

Implementation notes (2026-09-11): Phase 5 is implemented except `CKShare` wallet sharing (5.3), which is blocked on SwiftData not exposing the `NSPersistentCloudKitContainer` sharing APIs; its section states the blocker and what delivering it would take. Everything else compiles on iOS and macOS and is covered by tests. Three additive, defaulted models were added — debts and their payments, goals and their contributions, and record splits — all CloudKit-compatible in shape but **unverified against a deployed CloudKit schema**. Deleting a record now also removes its receipts and its split; deleting a debt or goal removes its payments or contributions; and Reset Wallet Data clears all of it. Each of those cascades is covered by a test, because orphaned rows would otherwise be invisible and permanent.

Two roadmap items were implemented deliberately differently from their wording, both noted in their sections: the text-size preference layers on top of Dynamic Type rather than replacing it, because overriding it would ignore an accessibility choice made at the system level; and savings-goal progress comes from recorded contributions rather than an account balance, so ordinary spending cannot silently undo it.

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
