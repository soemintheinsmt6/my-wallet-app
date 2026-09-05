# My Wallet

A SwiftUI wallet app built with modular MVVM and clean architecture, SwiftData storage, Combine, async/await, and a local Swift Package Manager package.

## Feature Status

Update this table whenever a feature is completed.

| Feature | Status | Current behavior |
| --- | --- | --- |
| Modular architecture | Complete | Domain, data and presentation modules with app-owned dependency injection |
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
| Labels / tags | Management complete | Create/edit a name and color; confirmed deletion; stable IDs for future record references |
| iCloud synchronization | Configured; device verification pending | Private CloudKit container and platform entitlements |
| Statistics dashboard, transactions, account deletion | Not implemented | Future work |

## Getting Started

Use Xcode with the project's 26.5 platform SDKs. The most recent build validation used Xcode 26.6 and Swift 6.3.3. Package tools require Swift 6.0 or newer.

1. Open `My Wallet.xcodeproj`.
2. Select the `My Wallet` scheme and your destination.
3. Configure signing and iCloud as described below, then Run.
4. Choose **Create Account**, fill in the fields, and save. Tap an account to edit it.
5. Open **Categories** to manage starter categories. Open a category, choose **Edit Category**, tap a subcategory to edit, or choose **Create Subcategory**. Use the Categories toolbar plus button to create another parent category.
6. Open **Labels** and choose **Create Label**. Tap a label to edit its name/color or delete it. Swipe or open the context menu to delete from the list; deletion requires confirmation.

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

Missing starter IDs are seeded when categories load. Untouched earlier seeds receive the new nature defaults; edited seeds, including explicit None choices, retain their settings. Renaming a starter keeps its ID. Locally simulated duplicate seed replicas resolve to one visible category, preferring the latest edit over seed defaults. Real-device iCloud convergence remains unverified. Category deletion, moving subcategories and transaction entry are not implemented yet.

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

Colors have no editor control. Future graphs/charts should reuse `category.colorToken.color` for marks and legends. Charts themselves are not implemented yet.

The bright palette follows the supplied visual reference, with Food & Drinks green and Life & Entertainment red. Category and account icons use white symbols on solid color backgrounds. Nature chips use white text on solid gray/green/blue/red fills for a consistent style; their colors remain independent of category and account colors.

The main category list shows only icons and names, without subcategory counts or nature chips. Category details show the card below the navigation title, with no large header icon. Nature chips have no dot and sit beside names in the detail and subcategory rows; subcategories use trailing chevrons. Nature remains editable in the editor.

Category and subcategory icons use 36-point backgrounds with 18-point symbols, with row content at least 44 points tall for comfortable tapping.

Category/subcategory edit sheets use the title **Edit**, a leading Name label with a trailing-aligned text field, and the nature selector without an extra chip. The editor has no icon/name preview.

## Labels / Tags

Labels have a trimmed name (1–80 characters) and one of ten colors: Blue, Teal, Green, Yellow, Orange, Red, Pink, Purple, Indigo or Gray. Names must be unique locally, ignoring case and accents. Labels are listed alphabetically and persist through SwiftData. Deleting a label removes it permanently; other labels, accounts and categories remain intact.

Record entry and attaching labels to records are not implemented yet. `WalletTag.id` provides stable identity for that future feature; renaming or recoloring a label preserves its ID. There are no pre-seeded labels. The CloudKit-compatible model is configured for the same private container, but live label sync needs device verification.

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
