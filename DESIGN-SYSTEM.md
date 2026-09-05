# Design System

[README](README.md) · [Architecture](ARCHITECTURE.md) · [Testing](TESTING.md)

## Current Foundation

The app uses native SwiftUI navigation, lists, grouped forms, sheets and semantic colors. This guide documents current conventions; there is no dedicated design-system package or centralized spacing token set yet.

Use system controls and text styles for new screens. Keep account-specific color independent of global action tint. `Assets.xcassets` contains app icon and accent-color slots; the accent asset currently has no custom color components.

## Color and Typography

`AccountColor+Presentation.swift` maps eight stored choices to SwiftUI colors: blue, teal, green, orange, red, pink, purple and gray. Account icons use the chosen color over a 10%-opacity background. Color choices include a name and selection checkmark.

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
