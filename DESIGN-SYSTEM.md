# Design System

[README](README.md) · [Architecture](ARCHITECTURE.md) · [Testing](TESTING.md)

## Current Foundation

The app uses native SwiftUI navigation, lists, grouped forms, sheets and semantic colors. This guide documents current conventions; there is no dedicated design-system package or centralized spacing token set yet.

Use system controls and text styles for new screens. Keep account-specific color independent of global action tint. `Assets.xcassets` contains app icon and accent-color slots; the accent asset currently has no custom color components.

## Color and Typography

`AccountColor+Presentation.swift` maps ten stored choices to SwiftUI colors: blue, teal, green, yellow, orange, red, pink, purple, indigo and gray. Account icons use white symbols on solid backgrounds in the chosen color, matching category icons. Color choices include a name and selection checkmark. The read-only category editor swatch is labeled Color.

Use primary text for names/content, secondary text for supporting information, tint for actions and red text for form errors. Do not communicate selection, errors or account type using color alone.

| Content | Current style |
| --- | --- |
| Account name and balance | `.headline`; balance uses monospaced digits |
| Account type | `.subheadline`, secondary |
| Exclusion label and alert limit | `.caption`, secondary |
| Form section labels and navigation titles | Native system styles |

## Layout Conventions

| Element | Current dimensions |
| --- | --- |
| Account row | 14-point horizontal spacing; 4-point vertical text spacing |
| Account icon background | 44 × 44 points; 12-point corner radius |
| Color swatch | 36-point circle; control minimum 44 × 60 points |
| Color grid | Adaptive 60-point columns; 12-point spacing |
| macOS account editor | Minimum 480 × 680 points |
| macOS currency picker | Minimum 400 × 500 points |

Treat these as existing values, not a mandatory global scale. Reuse them for related account UI; extract shared components when repeated patterns justify it.

## Components and Navigation

- `AccountsView`: notices above account rows, creation toolbar action, empty-state call to action and tap-to-edit sheets.
- `AccountEditorView`: shared create/edit form with Account, Color, In-app notifications and Actions sections.
- `CurrencyPickerView`: searchable currency names/codes with a selected checkmark.
- `ContentUnavailableView`: empty accounts and startup failures.
- `ProgressView`: loading and saving feedback.

Currency is interactive only on creation. Below/above toggles reveal their corresponding limit inputs. The Actions section currently contains only Exclude from stats.

## Category Components

The app has Accounts, Categories and Labels tabs. Label rows use 36-point solid-color tiles with 18-point white tag symbols, a name and trailing chevron; row content stays at least 44 points tall. The shared label editor uses a leading Name label, trailing-aligned text field, and the same ten-color grid pattern as accounts. Titles are Create Label and Edit. A destructive Delete Label action requires confirmation; deletion is also available through swipe/context actions. Preserve the draft and show inline errors when saving or deletion fails. The macOS label editor minimum is 440 × 460 points.

The app uses Accounts and Categories tabs, each with its own navigation stack. `CategoriesView` displays root names and relevant SF Symbols without subcategory counts or nature chips. `WalletCategory+Presentation` maps all 60 starter IDs to icons, preserving icons after renaming. Custom children fall back to their seeded parent's icon; other custom items use a tag. `CategoryDetailView` shows its card below the navigation title without a large header icon. Category and subcategory names share a horizontal row with their nature chips. Subcategory rows retain icons, use a trailing chevron and open the editor. Edit Category and Create Subcategory remain explicit actions.

`CategoryEditorView` shares a grouped form for create/edit at both levels. Edit sheets use the title Edit; create sheets retain Create Category/Create Subcategory. The editor has no icon/name preview. Name uses a leading label and a trailing-aligned text field. The parent is read-only for subcategories. A native picker offers None, Must, Need and Want without a separate badge below it. Seeds have suggested natures listed in README; custom items start at None. Use the established saving state and inline-error patterns, preserving the draft after validation/storage failures. The macOS editor minimum is 440 × 360 points.

## Category Color Tokens

Category identity colors and nature colors are independent. `CategoryColor` in WalletDomain defines fixed sRGB hex values (palette listed in README); `CategoryColor+Presentation` converts them to SwiftUI `Color`. Use `category.colorToken.color` for icons, future chart marks and chart legends. Do not derive category colors from nature, edited names, list order or Swift's randomized `Hasher`.

Starter roots each have a distinct fixed color. Children share their root color. Custom roots use deterministic UUID hashing into the fixed palette; repeated colors are possible, so future charts must include names and legends. These tokens are read-only and remain stable across renames, nature edits, launches and devices. Account color selection remains a separate editable feature.

`CategoryIcon` uses a white symbol on a solid category-color background, with a 36-point square, 18-point symbol and 10-point radius. Category and subcategory row content stays at least 44 points tall for tapping. The brighter palette follows the supplied reference, with Food & Drinks green and Life & Entertainment red. `CategoryNatureBadge` uses a dot-free solid capsule with white text: gray for None, green for Must, blue for Need, red for Want. Badges include a VoiceOver nature label and appear beside names in category details and subcategory rows, but not in the editor or main category list. Keep these semantic labels visible; color alone is insufficient.

## Account Icons

Mappings live in `AccountType+Presentation.swift`.

| Type | SF Symbol |
| --- | --- |
| Cash | `banknote` |
| Checking Account | `building.columns` |
| Credit Card | `creditcard` |
| Savings Account | `tray.full` |
| Investments | `chart.line.uptrend.xyaxis` |
| Loans & Mortgage | `house` |
| Other | `wallet.bifold` |

## Interaction and Content

Disable form editing, cancellation and interactive dismissal while saving. Preserve drafts after validation/storage errors. Use concise recovery messages. Account-list loading errors use an alert; save errors appear inline.

Display balances with the account currency and up to eight fractional digits. Input accepts the local decimal separator without grouping. Explain currency immutability and notification behavior in form footers. In-app balance notices use `bell.badge` and text identifying the breached limit.

## Accessibility and Review

Retain semantic text styles, readable labels, selected-state traits and explicit edit hints. Support keyboard interaction, larger text, light/dark appearance and adequate touch targets. Verify contrast for every swatch and avoid truncating essential amounts. These are review requirements; current automated tests do not establish accessibility or visual compliance.

Update this guide when adding shared visual conventions, and update [README.md](README.md) when the related feature is completed.
