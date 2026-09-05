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

## Derived Behavior

`balanceNotifications` includes accounts strictly outside enabled limits. `accountsIncludedInStats` omits excluded accounts without disabling alerts. No statistics calculations, currency conversion, transaction ledger or background balance-alert delivery exists yet.

## Category Hierarchy and Seeding

`WalletCategory` represents a root (`parentID == nil`) or a direct child identified by a root UUID. `CategoryUseCases` validates names, while `WalletStore+Categories` validates parent existence, rejects third-level nesting and enforces sibling-name uniqueness inside serialized persistence operations. Renaming never changes IDs or parent links. Category nature is independent at each level.

`CategorySeeds` defines 10 roots and 50 children with deterministic IDs. IDs currently encode group/child positions: preserve existing positions and IDs when evolving the seed catalog; append new entries rather than reordering old ones. Fetching categories inserts only missing IDs, saves them together, and preserves previously edited fields.

`CategoryRecord` uses CloudKit-compatible defaults and an optional parent UUID instead of a SwiftData relationship. No cascading delete exists. Root and child imports may arrive separately; children appear under their parent once it is available.

Seed natures now use category-specific suggestions. Earlier None values are upgraded only when `updatedAt` is still the Unix epoch, indicating an untouched seed. Any prior user save preserves its nature, even None. Icons remain presentation metadata keyed by stable seed IDs; no icon schema migration is needed, and renames do not change the assigned symbol.

Offline devices can independently create physical seed replicas. Fetches group by logical ID and select the latest `updatedAt`, breaking ties by `replicaID`; untouched seeds use the Unix epoch. Updates apply to all locally known replicas. This prevents duplicate visible seed categories and protects edits from later default imports, without deleting synced records. This is not server-side uniqueness: simultaneous custom-name creation can still conflict across devices, and concurrent edits use timestamps rather than field-level merging. Device verification is pending.

The app shares `CategoriesViewModel` through `AppDependencies` and presents Accounts/Categories tabs. Category observation uses the existing repository invalidation stream. A read can perform initial seed writes; subsequent reads do not rewrite existing seeds.

## Stable Category Colors

`WalletCategory.colorToken` derives a read-only `CategoryColor` from the root UUID. Seed roots map to explicit palette entries, while custom roots use deterministic FNV-1a hashing. Child categories use their parent UUID, matching root colors even when the root record has not yet synced. No stored color field, schema migration or mutable color API is introduced.

`CategoryColor.color` in WalletFeature exposes the sRGB conversion for UI and future charts. Changing a name or nature cannot change the token. Nature badge colors are separate presentation metadata. Preserve the palette values, ordering and hash algorithm when evolving the app to avoid changing historical chart colors.

## Adding a Feature

Define domain values and contracts, implement storage adapters, add presentation in a suitable feature target, and wire dependencies in the app. Add behavioral tests and migration coverage where needed. Update [README feature status](README.md#feature-status) and affected guides in the same change.
