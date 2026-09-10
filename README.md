# My Wallet

A SwiftUI wallet app built with modular MVVM and clean architecture, SwiftData storage, Combine, async/await, and a local Swift Package Manager package.

## Feature Status

Update this table whenever a feature is completed.

| Feature | Status | Current behavior |
| --- | --- | --- |
| Modular architecture | Complete | Domain, data and presentation modules with app-owned dependency injection |
| Appearance | Complete locally | Settings offers System, Light and Dark; choice persists on this device and applies across app windows |
| Temporary data reset | Debug builds only | Confirmed deletion of wallet data; retains theme, clears last-used entry defaults and dismisses open drafts |
| Account creation and editing | Complete | Name, current balance, type, color and saved settings |
| Account types | Complete | Cash, Checking Account, Credit Card, Savings Account, Investments, Loans & Mortgage, Other |
| Currency selection | Complete | Search by name/code during creation; immutable after saving |
| Local persistence | Complete | SwiftData storage, exact decimal strings and tested local schema upgrades |
| Balance notifications | Complete | In-app notices below a minimum or above a maximum; configurable independently |
| Exclude from stats | Setting complete | Persisted toggle and filtered account collection; excluded accounts still show alerts |
| Categories and subcategories | Complete | Create/edit names and independent None, Must, Need or Want natures; two-level hierarchy |
| Starter categories | Complete locally | 10 categories and 50 editable subcategories; repeat seeding preserves edits; cross-device validation pending |
| Category icons and suggested natures | Complete | Relevant icons for all 60 starter items; editable nature defaults with existing user choices preserved |
| Category and nature colors | Complete | Fixed category palette for UI/future charts; separate colored nature badges; colors cannot be edited |
| Labels / tags | Complete | Create/edit name and color; assign multiple labels to records; confirmed deletion detaches labels |
| Record creation | Complete locally | Expense, income and transfer; category/subcategory, most-used shortcuts, date/time, labels and optional details/photo |
| Budgets | Complete locally | Weekly/monthly/custom category or global limits, positive rollover, progress and threshold notices |
| Recurring transactions | Complete locally | Anchored schedules, launch/foreground catch-up, pause/cancel, skip/modify and idempotent occurrence receipts |
| Financial reports | Complete locally | Monthly/yearly/custom summaries, category breakdowns, running account statements and shareable PDF |
| Bill reminders | Complete locally | Due dates, recurrence, local notifications, calendar filtering and optional expense on payment |
| iCloud synchronization | Configured; device verification pending | Private CloudKit container and platform entitlements |
| Record editing/deletion | Complete locally | Edit all fields; confirmed detail, swipe and context deletion; atomic ledger balance recalculation |
| Account deletion | Complete locally | Impact summary and cascade/unlink strategies, including transfers |
| Category deletion | Complete locally | Delete or reassign children; Uncategorized fallback; retain at least one category |
| Statistics dashboard | Complete locally | Period/account/category/label filters, currency-separated totals, category charts, trends and reconstructed balance history |
| Record search and filtering | Complete locally | Search payee, note, amount, category and label names; combine with type/account/category/label/payment/date/amount filters; relevance, date or amount ordering and local recent searches |
| Home screen widgets | Complete locally; App Group provisioning and device rendering pending | Balance, this month, recent records, budget progress and quick-add widgets reading a shared snapshot the app writes; `mywallet://` deep links open the matching tab or editor |
| App lock | Complete locally; device biometric verification pending | Optional 4- or 6-digit passcode held as a salted keychain verifier, Face ID/Touch ID unlock, immediate/1-minute/5-minute auto-lock and throttled retries |
| Export and import | Complete locally; device file-picker verification pending | RFC 4180 record CSV and a versioned JSON backup, plus CSV import with header matching, a reviewed plan and duplicate detection; receipt images excluded |
| Onboarding | Complete locally; welcome step verified on simulator | First-launch welcome, first account, starter-category overview, optional monthly budget and Skip; completion is per-device and not synced |
| Multi-currency | Complete locally; live rate download and CloudKit migration verification pending | Optional home currency with ECB-backed rates, converted `≈` totals that never replace per-currency figures, per-record pinned rates and transfer gain/loss |
| Siri and Shortcuts | Complete locally; Siri and Spotlight device verification pending | Add Expense, Show Balance and Monthly Summary App Intents with account/category pickers, Siri phrases, and Spotlight indexing of names only |
| Apple Watch companion | Written but **not compiled** — watchOS platform not installed | Watch app with balance, today's spending and quick expense entry, plus two complications; syncs over WatchConnectivity. Watch app is not yet embedded in the iOS app |
| iPad and Mac layout | Complete locally; split view verified on an iPad simulator | Sidebar and split view at regular width with the dashboard beside statistics, ⌘N/⌘F/⌘1–⌘5 shortcuts, drag a record onto a category to refile it, and multi-window |

## Getting Started

Package sources are grouped by feature inside the existing Domain and Feature modules (`Accounts/`, `Categories/`, `Records/`, `Tags/`, `Legacy/`). Data sources separate `Models/` from `Persistence/`. Record amount, date/time and row components are extracted without changing the entry workflow or storage schema.

Use Xcode with the project's 26.5 platform SDKs. The most recent build validation used Xcode 26.6 and Swift 6.3.3. Package tools require Swift 6.0 or newer.

1. Open `My Wallet.xcodeproj`.
2. Select the `My Wallet` scheme and your destination.
3. Configure signing and iCloud as described below, then Run.
4. Open **Accounts**, choose **Create Account**, fill in the fields, and save. Tap an account to edit it.
5. Open **Categories** to manage starter categories. Open a category, choose **Edit Category**, tap a subcategory to edit, or choose **Create Subcategory**. Use the Categories toolbar plus button to create another parent category.
6. Open **Labels** and choose **Create Label**. Tap a label to edit its name/color or delete it. Swipe or open the context menu to delete from the list; deletion requires confirmation.
7. Open **Records** and choose **Add Record** or the plus button. Select Expense, Income or Transfer, enter an amount and complete General. More Details contains optional fields. Tap a saved record to view it.

The app targets iOS, macOS and visionOS 26.5. Package minimums are iOS 17, macOS 14 and visionOS 1. iOS Simulator and macOS builds have been verified; visionOS has not.

```sh
swift test --package-path Packages/WalletKit
xcodebuild -project 'My Wallet.xcodeproj' -scheme 'My Wallet' -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

## Account Behavior

The account color palette includes Blue, Teal, Green, Yellow, Orange, Red, Pink, Purple, Indigo and Gray. The category editor labels its read-only swatch **Color**.

Names are trimmed and limited to 80 characters. Amounts accept a sign, the local decimal separator, up to 18 integer digits and 8 fractional digits, without grouping separators. New accounts initially select the device currency, falling back to USD.

Balance alerts use strict comparisons: equality with a limit does not trigger an alert. When both alerts are enabled, minimum must be less than maximum. Notices clear when their conditions no longer hold.

Accounts created before currency/settings were introduced migrate to USD, zero balance, blue, alerts off and stats inclusion on. Currency cannot subsequently be edited. The legacy timestamp sample remains in the package/schema but is not the home screen.

## Categories

Categories and subcategories each have a name and nature: **None**, **Must**, **Need**, or **Want**. Starter items now have suggested natures: Must for obligations, Need for everyday essentials and savings, Want for discretionary spending, and None for income. These are editable defaults, not enforced budgeting rules. Custom items still start at None. A parent's nature does not overwrite its children's choices. Names are trimmed, limited to 80 characters, and checked for duplicates within the same parent (ignoring case and accents).

| Starter category | Icon (SF Symbol) | Nature | Subcategories (nature) |
| --- | --- | --- | --- |
| Food & Drinks | `fork.knife` | Need | Groceries (Need), Restaurant (Want), Fast Food (Want), Bar & Café (Want) |
| Shopping | `bag` | Want | Clothing & Shoes (Need), Electronics (Want), Personal Care (Need), Gifts (Want), Household Items (Need) |
| Housing | `house` | Must | Rent (Must), Utilities (Must), Maintenance & Repairs (Need), Home Insurance (Must), Furniture (Need) |
| Transportation | `bus` | Need | Public Transport (Need), Taxi & Ride-hailing (Want), Train (Need), Flights (Want), Bicycle (Need) |
| Vehicle | `car` | Need | Fuel (Need), Parking (Need), Service & Repairs (Need), Vehicle Insurance (Must), Registration & Tolls (Must) |
| Life & Entertainment | `theatermasks` | Want | Health & Fitness (Need), Hobbies (Want), Movies & Events (Want), Travel & Holidays (Want), Education (Need), Subscriptions (Want) |
| Communication (PC) | `laptopcomputer` | Need | Mobile Phone (Need), Internet (Need), Software & Apps (Need), Cloud Services (Need), Computer Accessories (Want) |
| Financial Expenses | `banknote` | Must | Bank Fees (Must), Loan Interest (Must), Taxes (Must), Loan Repayments (Must), Fines & Penalties (Must) |
| Investments | `chart.line.uptrend.xyaxis` | Need | Stocks (Want), Bonds (Need), Funds (Need), Real Estate (Want), Retirement Savings (Need) |
| Income | `arrow.down.circle` | None | Salary (None), Freelance (None), Business Income (None), Interest & Dividends (None), Gifts & Refunds (None) |

Every starter subcategory also has a matching icon. Seed icons follow stable IDs, so renaming an item preserves its icon. Custom subcategories fall back to their seeded parent's icon, and other custom items use a tag icon.

Missing starter IDs are seeded when categories load. Untouched earlier seeds receive the new nature defaults; edited seeds, including explicit None choices, retain their settings. Renaming a starter keeps its ID. Locally simulated duplicate seed replicas resolve to one visible category, preferring the latest edit over seed defaults. Real-device iCloud convergence remains unverified. Category deletion can delete its children or move them to another root; duplicate sibling names must be resolved first. Records keep an Uncategorized fallback, and the last category cannot be deleted. Deleted IDs retain a tombstone so starter seeding does not recreate them.

## Category Colors

Nature badges use **None: gray**, **Must: green**, **Need: blue**, and **Want: red**, with text labels retained. Category colors are separate and never change when names or natures are edited. Subcategories share their parent's color. Custom root colors are automatically selected from the palette using their stable UUID, consistently across devices; colors may repeat for custom roots.

| Category | Fixed color |
| --- | --- |
| Food & Drinks | Bright green `#55D80B` |
| Shopping | Sky blue `#4AC3F2` |
| Housing | Orange `#FFA51F` |
| Transportation | Blue-gray `#78909C` |
| Vehicle | Violet `#AA00FF` |
| Life & Entertainment | Red `#FF4136` |
| Communication (PC) | Indigo `#536DFE` |
| Financial Expenses | Teal `#00BFA5` |
| Investments | Pink `#FF4081` |
| Income | Amber `#FFC329` |

Colors have no editor control. Future graphs/charts should reuse `category.colorToken.color` for marks and legends. Statistics charts use these same fixed colors.

The bright palette follows the supplied visual reference, with Food & Drinks green and Life & Entertainment red. Category and account icons use white symbols on solid color backgrounds. Nature chips use white text on solid gray/green/blue/red fills for a consistent style; their colors remain independent of category and account colors.

The main category list shows only icons and names, without subcategory counts or nature chips. Category details show the card below the navigation title, with no large header icon. Nature chips have no dot and sit beside names in the detail and subcategory rows; subcategories use trailing chevrons. Nature remains editable in the editor.

Category and subcategory icons use 36-point backgrounds with 18-point symbols, with row content at least 44 points tall for comfortable tapping.

Category/subcategory edit sheets use the title **Edit**, a leading Name label with a trailing-aligned text field, and the nature selector without an extra chip. The editor has no icon/name preview.

## Labels / Tags

Labels have a trimmed name (1–80 characters) and one of ten colors: Blue, Teal, Green, Yellow, Orange, Red, Pink, Purple, Indigo or Gray. Names must be unique locally, ignoring case and accents. Labels are listed alphabetically and persist through SwiftData. Deleting a label removes it permanently; other labels, accounts and categories remain intact.

Records reference stable `WalletTag.id` values; renaming/recoloring preserves assignments. Deleting a label detaches it from records without deleting records or changing balances. There are no pre-seeded labels. Live label sync needs device verification.

## Records

Date & Time shows plain trailing text (such as Today, 6:18 PM), without gray capsules. Tap the row to open the native date/time picker popover. Changes apply immediately; tap outside to dismiss. There is no Done button.

The compact entry header uses a smaller currency pill and a 60-point scaled amount with reduced spacing. The bottom Save area is shorter; tapping blank space or section headers dismisses the keyboard, and scrolling supports interactive dismissal.

Amounts display locale-aware digit separators without rounding the input. New drafts restore the account and payment type from the last successfully saved record on this device (transfers remember the From account). Cancelled drafts do not change these defaults; unavailable accounts remain unselected. Account rows always use a fixed blue wallet icon.

Record-entry rows use aligned 36-point icon slots, 18-point symbols and a compact 10-point icon/text gap. Account icons use fixed white wallet symbols on blue tiles, matching category container dimensions. The amount remains editable and autofocused with its cursor hidden.

The amount field focuses when Add Record first opens. Currency stays hidden until an account is selected. Account, transfer destination and payment type use leading labels with trailing chevrons and push selection lists; choosing an item returns to the draft. Category icons reuse the category list's white-on-color tiles.

The Add Record title is inline. The reference-inspired layout uses a left currency badge, large right-aligned amount, full-width icon-led rows and a fixed bottom Save button. Expenses show a red minus, income a green plus, and transfers no prefix; prefixes are visual only, while saved amounts remain positive. Save stays disabled until required input is valid.

Choose Expense, Income or Transfer and enter a positive amount. General contains account, category or subcategory, date/time and multiple labels. Transfers use distinct From/To accounts and allow no category; expense/income require one. Most-used shortcuts rank up to six categories/subcategories by saved usage for the selected record type, with recent use breaking ties. They appear after records exist.

More Details supports note, payee, payment type and one photo from the photo library. Photos are downsampled to at most 1,600 pixels, re-encoded as JPEG and limited to 5 MB. Saved attachments load when viewing details. Camera capture is not included.

Expenses subtract from balances, income adds, and transfers debit/credit their selected accounts. Different-currency transfers require an explicit received amount; no exchange rate is fetched. Account balances derive from the stored starting/adjustment balance plus records. Manually editing a balance preserves existing records. All saved records affect balances immediately, including future-dated entries. Saved records can be edited, including account, type, transfer destination, labels and photo replacement/removal. Updates preserve identity and replace the ledger effect atomically. Delete from record details, swipe actions or context menus after confirmation; both transfer legs and attached photo data are removed. Recurring scheduling is available through Repeat on new records; live iCloud verification remains pending.

Delete an account from its swipe/context action to review its current balance, record count and transfer count. Keep Records removes only links to that account and preserves the surviving transfer leg. Delete Records removes associated records/photos and reverses their effects on other accounts. Unlinked records remain visible with currency snapshots; choose valid accounts to edit them again.

Search the Records list to match a payee, note, amount, category name (its parent name also matches) or label name. Every word you type must match one of those fields, ignoring case and accents; a numeric word matches an exact amount first, then amounts containing those digits. Submitted searches are remembered on this device as suggestions until you clear them or reset wallet data. The Filters button combines search with record type, accounts, categories, labels, payment type, an inclusive date range and minimum/maximum amounts, and sorts by relevance, date or amount. Filter groups narrow each other while values inside one group widen it, so choosing two labels matches records carrying either. A category selection includes its subcategories and hides uncategorized records; an account selection matches either side of a transfer. Amount bounds compare the record's own amount without currency conversion.

The **Statistics** tab supports week, month, year and inclusive custom date ranges, account/category/label filters, expense/income category charts, daily/weekly/monthly trends, top spending categories and account balance history. Selecting a root category includes its children. Excluded accounts and unlinked activity are omitted. Currency totals are separate; transfers affect balance history only. History respects account and currency filters, while category/label filters affect activity charts. History is reconstructed from current base balances, so manual balance corrections apply retrospectively. Automatic exchange rates are not implemented.

## Settings

Open **Settings → Appearance** to choose System, Light or Dark. System follows the device appearance; the choice is saved locally, not synced through iCloud.

Debug builds also show **Temporary Development Tools → Reset Wallet Data**. Confirmation deletes accounts, records (including photos), labels, category edits/custom categories and legacy entries. Last-used account/payment defaults are cleared, while the theme is kept. Open drafts/navigation are discarded in all app windows after success. Starter categories are seeded again on the next category load.

Reset is irreversible in the app and may propagate deletions through iCloud. It is not a local-cache-only wipe, secure erasure or a purge of data that has not yet synced; later remote imports may reappear. The reset button is absent from release builds. No personal wallet data was deleted during implementation.

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

## Financial Planning (Phase 2)

Open **Planning** for Budgets, Recurring, Bills and Reports. **Home** summarizes balance, this month's activity, budget progress, upcoming bills and recent records. **More** holds Accounts, Categories, Labels and Settings.

- **Budgets:** Create weekly, monthly or custom-period limits for one category (including its children) or overall spending. Currency totals remain separate and excluded accounts are omitted. Weekly/monthly periods are anchored to the chosen start date. Custom end dates are exclusive. Positive unused funds can roll into the next period; overspending does not reduce the next period's allowance. Budget vs. actual has a date selector, and current progress also appears in Statistics and category details. Enable notices at 80% and 100% and grant notification permission.
- **Recurring:** Enable Repeat in Add Record. The first record saves immediately; subsequent occurrences are generated when the app opens, becomes active, or you choose Generate Due Records Now. Daily, weekly, biweekly, monthly and yearly rules support an end date and/or count including the first record. Dates retain the original time zone and month-end anchor. Pause/resume/cancel future generation, edit future details or the schedule, and skip/modify upcoming occurrences. Moving one occurrence does not delay others. Generation processes at most 500 occurrences per series per refresh; refresh again for longer catch-up. Cancel/pause preserves existing records. Missing linked references must be repaired or the affected series paused before catch-up can succeed.
- **Bills:** Create a bill with amount, currency, due date and optional account/category links. Choose an on-date or 1–30-day advance notification. Calendar mode filters the next unpaid occurrences by day; overdue entries are highlighted. Mark Paid Only changes no balances. Mark Paid and Add Expense saves one expense and advances the bill atomically. Repeated confirmation does not duplicate a payment. For repeating bills, pay each outstanding occurrence in order; editing a bill does not rewind already paid occurrences.
- **Reports:** Choose monthly/yearly/custom periods and a currency for a financial summary, or an account for its statement. Summaries exclude transfers and excluded accounts; statements include the selected account's transfer legs. Prepare PDF creates a paginated report snapshot, then Share PDF opens the system sharing interface. Statement history uses current base balances, so manual balance corrections apply retrospectively.

Notifications require system permission. The app refreshes up to 60 eligible notices on activity, removes obsolete pending requests, and remembers delivered bill occurrences/budget thresholds locally. No push server or periodic background execution is required. Device notification delivery, simultaneous offline CloudKit schedule generation, and accessibility/UI interactions remain manual verification items. Local occurrence IDs/receipts protect retries; they do not establish global uniqueness across independently syncing CloudKit replicas.

Phase 2 adds `BudgetRecord`, `RecurringSeriesRecord`, `ScheduledOccurrenceRecord`, and `BillReminderRecord`. Their optional Codable payloads and default IDs are compatible with the configured CloudKit model requirements. Schedule/occurrence payloads use external storage for attached photos. Existing model fields, container IDs and entitlements are unchanged. Local migration/reopening tests preserve prior accounts, exact decimal values, photos and occurrence receipts; deploy the additive CloudKit schema before releasing. Reset Wallet Data also removes all plans and pending notices after refresh.
