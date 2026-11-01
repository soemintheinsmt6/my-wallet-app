# Architecture

[README](README.md) · [Testing](TESTING.md) · [Design system](DESIGN-SYSTEM.md)

## Module Boundaries

The local package is defined in `Packages/WalletKit/Package.swift`. It has three library targets and no third-party dependencies.

| Layer | Location | Responsibility |
| --- | --- | --- |
| Composition | `My Wallet/App/` | Shared startup, dependency injection and startup errors |
| Domain | `Sources/WalletDomain/` | Sendable values, repository contracts and validated use cases |
| Data | `Sources/WalletData/` | SwiftData models, persistence actor and change notifications |
| Presentation | `Sources/WalletFeature/` | SwiftUI screens, form state and Combine view models |

Source paths above are relative to `Packages/WalletKit/` except the app path.

Domain and Feature sources are grouped into `Accounts/`, `Categories/`, `Records/`, `Tags/` and `Legacy/`. Data uses `Models/` for persisted types and `Persistence/` for container/repository/actor code. These folders are organization within the same three SwiftPM targets, not additional modules; imports and public contracts remain unchanged.

`RecordEditorView` owns draft state, focus, navigation and saving. Its named amount/general/details sections compose `RecordAmountField`, `RecordDateTimeField` and `RecordFormRow`; the date component owns only its popover state. `RecordUseCases` has its own domain file. Account persistence lives in `WalletStore+Accounts`, alongside category/tag/record actor extensions. Preserve model names and stored fields when moving files; this refactor introduces no schema migration.

```text
App → WalletFeature → WalletDomain
App → WalletData    → WalletDomain
App → WalletDomain
```

The feature module never imports the data module. Views do not access SwiftData. `AppDependencies` creates the concrete repository, use cases and view model; one app-owned `AppBootstrap` shares that graph across windows.

## Account Data Flow

```text
AccountEditorView
  → AccountsViewModel
  → AccountUseCases
  → AccountRepository
  → SwiftDataWalletRepository
  → WalletStore (@ModelActor)
  → AccountRecord / ModelContainer
```

`AccountUseCases` validates names, currencies, decimal ranges and notification limits. The update contract accepts only ID, name, type and settings; currency and creation metadata remain unchanged.

`Account` and `AccountSettings` cross module boundaries as values. `AccountRecord` is the persistence representation. Decimal amounts are stored as canonical strings to avoid binary floating-point loss. Color and type use stable raw values.

## Concurrency and Observation

Repository interfaces and view models are `@MainActor`. Repository operations are asynchronous and delegate disk work to `WalletStore`, created with its container in a detached task. Short-lived contexts isolate operations and avoid retaining stale fetched objects.

Successful saves and Core Data remote-change notifications invalidate account lists. A Combine notification subscription hops to the main actor, then yields into subscriber-specific, bounded `AsyncStream` instances. SwiftUI `.task` owns observation and cancels it on disappearance.

Foreground activation and pull-to-refresh reload local data. Load-generation checks prevent older loads replacing newer results. Saving disables form actions; failures retain the draft. A successful save can dismiss the form even if the subsequent list refresh reports an error.

## Persistence and CloudKit

`WalletPersistence` supports private CloudKit, local-only and in-memory configurations. Production app wiring currently chooses `iCloud.com.app.My-Wallet`.

Models provide defaults and avoid unique constraints. Future relationships should remain CloudKit-compatible, with optionality and appropriate inverses. Review schema evolution before changing field names, types or defaults; test upgrades against an earlier schema. Local migration tests do not verify production CloudKit schema deployment.

The legacy `Item` and timestamp feature remain for compatibility. Tests cover adding accounts to the package's earlier item schema and adding settings to the earlier account schema. Upgrades from the original pre-modular starter installation need separate verification.

`AccountRecord.symbolValue` (2026-11-01) is an additive String with an empty default, mapped to `AccountSettings.symbol` (`nil` when empty, meaning the type's icon). It syncs with the account, unlike category icon overrides, which stay local in `CategorySymbolStore`. Older stores migrate with no chosen icon; the existing migration test opens a store written before it. Deploy the CloudKit development schema to production before release, or production iCloud will not carry the field. The JSON backup carries it as an optional key, so older backups still decode.

## Derived Behavior

`balanceNotifications` includes accounts strictly outside enabled limits. `accountsIncludedInStats` omits excluded accounts without disabling alerts. Statistics derives filtered, currency-separated totals and reconstructed balance history from domain values. Automatic currency conversion and background balance-alert delivery are not implemented.

## Category Hierarchy and Seeding

`WalletCategory` represents a root (`parentID == nil`) or a direct child identified by a root UUID. `CategoryUseCases` validates names, while `WalletStore+Categories` validates parent existence, rejects third-level nesting and enforces sibling-name uniqueness inside serialized persistence operations. Renaming never changes IDs or parent links. Category nature is independent at each level.

`CategorySeeds` defines 10 roots and 50 children with deterministic IDs. IDs currently encode group/child positions: preserve existing positions and IDs when evolving the seed catalog; append new entries rather than reordering old ones. Fetching categories inserts only missing IDs, saves them together, and preserves previously edited fields.

`CategoryRecord` uses CloudKit-compatible defaults and an optional parent UUID instead of a SwiftData relationship. An optional `deletionDate` tombstone hides deleted logical categories after replica resolution and prevents starter reseeding. Category deletion reassigns or tombstones children and clears locally known record references in one save. Root and child imports may arrive separately; children appear under their parent once it is available.

Seed natures now use category-specific suggestions. Earlier None values are upgraded only when `updatedAt` is still the Unix epoch, indicating an untouched seed. Any prior user save preserves its nature, even None. Icons remain presentation metadata keyed by stable seed IDs; no icon schema migration is needed, and renames do not change the assigned symbol.

Offline devices can independently create physical seed replicas. Fetches group by logical ID and select the latest `updatedAt`, breaking ties by `replicaID`; untouched seeds use the Unix epoch. Updates apply to all locally known replicas. This prevents duplicate visible seed categories and protects edits from later default imports, without deleting synced records. This is not server-side uniqueness: simultaneous custom-name creation can still conflict across devices, and concurrent edits use timestamps rather than field-level merging. Device verification is pending.

The app shares `CategoriesViewModel` through `AppDependencies`. Category observation uses the existing repository invalidation stream. A read can perform initial seed writes; subsequent reads do not rewrite existing seeds.

## Stable Category Colors

`WalletCategory.colorToken` derives a read-only `CategoryColor` from the root UUID. Seed roots map to explicit palette entries, while custom roots use deterministic FNV-1a hashing. Child categories use their parent UUID, matching root colors even when the root record has not yet synced. No stored color field, schema migration or mutable color API is introduced.

`CategoryColor.color` in WalletFeature exposes the sRGB conversion for UI and future charts. Changing a name or nature cannot change the token. Nature badge colors are separate presentation metadata. Preserve the palette values, ordering and hash algorithm when evolving the app to avoid changing historical chart colors.

## Labels / Tags

`WalletTag` is a Sendable value with UUID identity, name and `TagColor`. The UI calls it a Label. `TagUseCases` handles trimmed name validation and delegates to `TagRepository`. `WalletStore+Tags` performs create, update and delete in isolated contexts and checks duplicate names inside its serialized operations. Edits preserve identity; repeated deletion is safe. `TagRecord` is an additive CloudKit-compatible model without unique constraints.

`TagsViewModel` observes the existing invalidation stream and is shared through `AppDependencies`. `TagsView` appears in the Labels tab; saves and deletions refresh the list. Name uniqueness ignores case/accents locally; simultaneous same-name creation on separate offline devices is not globally prevented.

Records reference label UUIDs. Deletion removes the selected ID from locally known records and deletes the label in one save, retaining financial records. Concurrent offline assignments/deletions require device verification; missing label IDs are not displayed.

## Record Ledger

`RecordEditorView → RecordsViewModel → RecordUseCases → RecordRepository → WalletStore` validates and saves `TransactionRecord`. Domain drafts contain exact Decimal amounts, account/category UUIDs, label IDs, timestamp, optional details and photo data. Transfers validate distinct existing accounts; cross-currency transfers require a received amount. A stable editor UUID makes repeated creation requests locally idempotent.

Account reads derive balances from stored base balances plus ledger deltas. Editing an account's displayed balance subtracts its existing ledger delta before storing the new base. Record creation saves one ledger item rather than independently updating synchronized account counters. This does not establish conflict-free concurrent manual balance edits; CloudKit convergence remains unverified.

PhotosPicker data is downsampled off the main actor and re-encoded without copying source metadata. SwiftData external storage holds the JPEG. List values carry only `hasPhoto`; detail views fetch attachment bytes lazily. Most-used category rankings derive from exact category IDs and record kind, then frequency and recency. The app exposes Dashboard, Records, Statistics, Planning and More tabs; More carries Accounts, Categories, Labels and Settings.

`WalletDomain/Debts/`, `Goals/` and `Sharing/` hold claims against other people, savings targets and split bills. None of them are accounts: a debt is a claim rather than money held, goal progress comes from recorded contributions rather than a balance, and a split records both shares and payments. Their pure calculations — per-person netting, rate projection, equal-share rounding and settlement suggestions — are `nonisolated` statics so they need no actor and are directly testable. Their persistence follows the planning models: one defaulted `payload` column of Codable JSON per row, with the foreign key kept as a real column so cascades can find rows without decoding them.

`WalletDomain/Receipts/` and `WalletData`'s `ReceiptRecord` keep scanned pages in their own model, linked by a plain `recordID`, so a ledger fetch never carries image bytes. Record deletion and wallet reset both remove pages in the same save that removes their owner. `WalletDomain/Insights/` holds spending comparisons, anomaly detection and streaks as pure calendar-injectable calculations. `WalletNotificationClient.synchronize` takes the identifier prefixes its caller owns, so planning and insight notices cannot cancel one another.

`WalletDomain/Currency/` holds conversion as pure `Decimal` arithmetic — `ExchangeRateSet`, `CurrencyConverter` and the `ExchangeRateProviding` contract — while `WalletData/Remote/` owns the network client and the on-disk rate cache, keeping the dependency direction pointing at the domain. `CurrencyViewModel` reaches deep views through a SwiftUI environment value instead of being threaded through every presenter. The per-record pinned rate is one optional, defaulted `manualRateValue` on `TransactionRecord`, chosen so the addition stays a lightweight CloudKit-compatible migration.

`WalletDomain/DataExchange/` holds the file formats as pure values: RFC 4180 `CSV`, the `RecordCSV` column schema and parsing, the versioned `WalletArchive`, and `ImportPlanner`, which resolves parsed rows against the wallet and classifies each as importable, duplicate or problem. `DataExchangeViewModel` in the feature module only performs I/O and writes imported rows through `RecordUseCases`, so imports get the same validation and balance handling as the editors.

The `WalletWidgets` extension target is a second consumer of the domain and deliberately does not share the store. `WalletDomain/Widgets/` owns two contracts between the processes: `WalletSnapshot`, a display-resolved summary, and `WalletDeepLink`, the `mywallet://` URL vocabulary. The app builds snapshots with `WalletSnapshotBuilder` and writes them through `WalletSnapshotStore` into the `group.com.app.My-Wallet` App Group container; `WalletSnapshotCoordinator` decides when. The extension links `WalletDomain` only, reads the snapshot, and never writes. Keeping the SwiftData/CloudKit store in the app container avoids migrating existing installs, at the cost of the widget showing data only as fresh as the app's last run. Records support create/read/update/delete. Updates apply all fields to the existing logical record in one context save; deleting a record removes photo data and the ledger effect.

## Settings and Maintenance

New settings code uses responsibility subfolders: Domain `Settings/Repositories` and `Settings/UseCases`; Feature `Settings/Models`, `Settings/ViewModels` and `Settings/Views`; Data `Persistence/Settings`. Shared preference keys live in `Shared/Preferences`. Continue creating relevant subdirectories as features grow instead of flattening them.

`AppAppearance` maps System to no SwiftUI color-scheme override. The app root observes the same local preference as Settings and applies the selected appearance. `SettingsViewModel` calls `ResetWalletUseCase` through `WalletResetRepository`. The store deletes fetched model instances in one isolated-context save, then the repository publishes invalidation. This uses ordinary CloudKit deletion rather than removing database files.

After success, only last-used record preferences are removed; a shared reset generation recreates tab/navigation state across windows. Failure retains preferences and navigation and exposes an error. The destructive control is compiled only in debug builds. Category seeding remains unchanged, and remote imports/concurrent offline writes require live-device verification.

## Adding a Feature

Define domain values and contracts, implement storage adapters, add presentation in a suitable feature target, and wire dependencies in the app. Add behavioral tests and migration coverage where needed. Update [README feature status](README.md#feature-status) and affected guides in the same change.

## Core Deletion and Statistics

Account deletion either removes associated records/photos or clears only the deleted account link. Kept transfer records continue to affect surviving accounts. Cascade removal reverses the surviving side through the derived ledger. Domain impact summaries expose the current account balance and affected record/transfer counts before confirmation. All mutations publish repository invalidations after saving.

`CategoryRecord.deletionDate` is an additive optional Date with a nil default. Older stores migrate with categories visible; migration/reopening regression tests cover this. Logical replica resolution occurs before filtering tombstones. No CloudKit container or entitlement changes are needed, but deploy the additive schema before production use and verify offline edits/deletions on devices. Concurrent offline edits remain timestamp-resolved, and references arriving after a deletion can be displayed as unavailable/Uncategorized.

`WalletStatistics.calculate` is a pure domain calculation over records, accounts and categories. It excludes accounts marked `excludeFromStats`, groups activity by currency and category, includes children for root category filters, and excludes transfers from income/expense totals. Swift Charts is confined to WalletFeature. Balance history reconstructs current base balances plus dated ledger deltas; future records are removed from earlier history, while manual balance corrections remain retrospective. Category/label filters do not alter account balance history. Stats observes the shared RecordsViewModel invalidation stream.

`WalletStatistics.expensesByLabel` groups the same window's expenses by label with an unlabeled entry, splitting a record that carries several labels evenly so both breakdowns sum to the same total. The Dashboard's chart cards roll subcategory totals up to their top-level category and fold past six parts into "Other" (`DashboardBreakdown`); its Balance Trend reuses `balanceHistory` over the last 30 days at day granularity. `AccountActivity` (WalletFeature) computes one account's income, expenses and touching records over an `ActivityPeriod` window for `AccountDetailView`; unlike statistics it includes accounts excluded from stats, since exclusion hides an account from wallet-wide figures, not from itself. `DashboardConfiguration` no longer stores a period or account scope; older saved arrangements still decode with those keys ignored, and `DashboardViewModel` places newly added cards (Accounts, the chart cards) beside their natural neighbor in an existing arrangement instead of at the bottom.

## Financial Planning

Domain values live in `Budgets/`, `Records/RecurrenceRule.swift`, `Reminders/` and `Reports/`. `PlanningViewModel` coordinates budget, recurring and bill repositories, reuses `RecordsViewModel` for ledger snapshots, and depends on the `WalletNotificationClient` contract. The app composition root injects `LocalWalletNotifications`, keeping UserNotifications/system permission handling outside persistence. `WalletTabsView` observes planning changes and requests catch-up on startup/foreground. Errors retain loaded state and do not prevent opening the wallet.

Four additive SwiftData models persist Codable payloads without unique constraints or relationships: budgets, series, occurrence receipts and bills. Future payload evolution must preserve Codable keys or provide decoding defaults/migrations. Larger schedule/override payloads use external storage. Domain Decimal values survive encode/decode at full precision. Existing schemas remain unchanged; migration and disk reopening are tested. Reset deletes the new models in the same context as the existing wallet data.

Record insertion now accepts a caller-owned context. Initial recurring creation saves the original transaction and series together. Generation saves ledger records, completion receipts and cursors atomically. Deterministic occurrence UUIDs use SHA-256 over kind, owner UUID and occurrence index. Completed receipts survive ordinary record deletion; retries do not recreate deleted occurrences. Modified dates are processed independently of the regular cursor. Pause/cancel preserves history. Catch-up is bounded to 500 processed items per series per invocation. Local atomicity does not guarantee uniqueness after concurrent independent CloudKit writes; multi-device convergence remains unverified.

Bills store an immutable-after-payment anchor and a next-unpaid index. Marking paid optionally calls the same ledger insertion inside one save, then advances the index; stale/repeated payment confirmations are no-ops. Budgets calculate positive rollover from period expense totals in the chosen currency; root category budgets include direct children and excluded accounts are omitted.

`AccountStatement` calculates exact Decimal running balances in Domain. `ReportPDF` uses CoreText and a CoreGraphics PDF context, paginating text without splitting words at arbitrary character counts. Reports are generated off the main actor into temporary PDFs and shared through SwiftUI ShareLink. Sample output is checked with PDFKit text extraction and rendered with Poppler for visual QA.

Notifications are reconciled by stable bill-occurrence/budget-threshold IDs. The app remembers scheduled/delivered IDs, limits the pending set to 60, removes obsolete requests and presents foreground banners. Permission is requested only from explicit editor actions. OS delivery, entitlement provisioning, timezone changes and accessibility require device verification.

## Record Search and Filtering

`RecordQuery` and `RecordSearch` are additive domain values in `Records/`. `RecordSearch.run` is a pure calculation over the records, categories and labels already loaded by `RecordsViewModel`; no repository contract, persisted model or fetch predicate changes. Searching costs one in-memory pass per body evaluation and scales with the loaded ledger rather than the store. Move ranking into a store-side predicate only if the loaded ledger stops fitting in memory.

Text is tokenized on whitespace, and every term must match at least one of payee, note, category name (plus its parent's), label name or amount, compared with `caseInsensitive` and `diacriticInsensitive` options. Scores weight exact, word-prefix and containing matches per field, then sum across terms. Amount terms normalize a comma decimal separator, compare exact Decimal equality first, and otherwise match the canonical Decimal description, which is never grouped or localized. Sorting is total: relevance falls back to newest, and every order ends on the record UUID so equal values keep a stable position across reloads.

Filter groups intersect while values inside one group union, and an empty group means no restriction. Root category selections expand to direct children, and an active category filter excludes uncategorized records. Account filters match either transfer leg. `start`/`end` follow the exclusive-end ledger convention; amount bounds are inclusive and compare the record's own amount without conversion.

`RecordFilterView` mutates a private copy of the query and assigns it on Apply, so cancelling changes nothing. Recent searches live in `RecentSearches`, a capped newline-separated `AppStorage` string under `Shared/Preferences`, cleared by `SettingsViewModel.resetData`. That history is device-local and intentionally not synchronized.
