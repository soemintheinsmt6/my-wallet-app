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

The app has Records, Statistics, Accounts, Categories, Labels, Planning and Settings tabs. Label rows use 36-point solid-color tiles with 18-point white tag symbols, a name and trailing chevron; row content stays at least 44 points tall. The shared label editor uses a leading Name label, trailing-aligned text field, and the same ten-color grid pattern as accounts. Titles are Create Label and Edit. A destructive Delete Label action requires confirmation; deletion is also available through swipe/context actions. Preserve the draft and show inline errors when saving or deletion fails. The macOS label editor minimum is 440 × 460 points.

Each tab has its own navigation stack. `CategoriesView` displays root names and relevant SF Symbols without subcategory counts or nature chips. `WalletCategory+Presentation` maps all 60 starter IDs to icons, preserving icons after renaming. Custom children fall back to their seeded parent's icon; other custom items use a tag. `CategoryDetailView` shows its card below the navigation title without a large header icon. Category and subcategory names share a horizontal row with their nature chips. Subcategory rows retain icons, use a trailing chevron and open the editor. Edit Category and Create Subcategory remain explicit actions.

## Record Components

Record UI sources live in `Sources/WalletFeature/Records/`. `RecordAmountField` owns amount presentation, `RecordDateTimeField` owns the date popover, and `RecordFormRow` centralizes row geometry. `RecordEditorView` keeps draft/focus/navigation state and composes these controls; reuse the extracted components instead of copying their layout.

Date & Time uses primary-colored, trailing, locale-aware date/time text with relative day labels and no capsule background. The row opens a native graphical date/time picker in a popover without Done; changes update the draft immediately and tapping outside dismisses it.

The amount header uses a 60-point Dynamic Type-scaled font, 12-point stack spacing and 4-point vertical amount padding. Currency is a subheadline pill with 12 × 6-point padding. Save uses a 28-point minimum label height plus native button insets and a 10-point vertical footer margin. Blank-background/section-header taps clear focus for all entry text fields without adding a tap gesture to interactive controls.

Display locale-aware grouping in the main amount, preserving fractional zeros and incomplete decimal input. Account rows use a fixed white wallet on blue, independent of selection. New drafts restore the locally last-saved account/payment type; persist defaults only after a successful save.

All record-row leading icons, including Attach Photo, use 18-point symbols in 36 × 36-point slots, with a 10-point text gap and aligned dividers. Account icons use fixed white wallet symbols on blue with 10-point rounded corners, matching category tiles. The amount input uses clear tint to hide its insertion cursor while retaining focus and keyboard input.

Focus the amount once on initial presentation, not again after returning from selection. Hide the currency capsule without a selected account. Account and Payment Type rows have leading labels, optional trailing values and chevrons; push selection lists with checkmarks and return after choosing. Transfer destination excludes the source account. Reuse `CategoryIcon` for selected categories and a gray white-symbol tile when unselected.

Use an inline Add Record navigation title on mobile. A segmented selector sits above a left currency capsule and right-aligned amount using a Dynamic Type-scaled 60-point regular font with monospaced digits. Expense amounts have a red minus prefix, income amounts a green plus, and transfers use primary text without a prefix. Keep signs outside the stored value. Full-width rows use 36-point leading icon slots, inset dividers and muted section-header bands. A safe-area bottom Save button remains disabled until required input is valid. Missing required categories display Required in red; Labels has a plus action.

Record creation uses an Expense/Income/Transfer segmented selector and amount input. General groups account (From/To for transfers), category, most-used shortcuts, date/time and labels. More Details groups optional note, payee, payment type and library-photo attachment. Different-currency transfers reveal a received amount input.

The searchable category sheet allows either a root or child selection and reuses fixed category colors/icons; most-used entries include parent context. Label selection supports multiple checkmarks. Photo loading shows progress and disables saving; previews offer replacement/removal. Record rows open details with Edit and confirmed Delete actions. Edit reuses the record form and loads original photos before permitting saves. Retain textual type labels alongside red expense, green income and blue transfer indicators.

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

## Settings

Settings has its own tab, with a native System/Light/Dark segmented selector. Theme is applied at the app root so sheets and all tabs share the same choice. Use semantic colors for surfaces and text.

Debug-only Temporary Development Tools contains a destructive Reset Wallet Data action and an explicit warning about iCloud propagation. Require confirmation, disable the tab interface during reset, show progress/errors, and discard open drafts after success. No reset action is visible in release builds.

## Accessibility and Review

Retain semantic text styles, readable labels, selected-state traits and explicit edit hints. Support keyboard interaction, larger text, light/dark appearance and adequate touch targets. Verify contrast for every swatch and avoid truncating essential amounts. These are review requirements; current automated tests do not establish accessibility or visual compliance.

Update this guide when adding shared visual conventions, and update [README.md](README.md) when the related feature is completed.

## Statistics and Destructive Actions

Statistics uses native period and filter pickers, currency-formatted summary rows, labeled donut charts, a spending bar chart, a balance-history line chart and a top-category list. Chart marks and legends reuse category color tokens with a gray Uncategorized fallback; names and amounts accompany color. VoiceOver marks expose dates/categories and formatted amounts. Empty periods show explicit no-activity text. Totals remain separate by currency and the history explanation stays visible.

Record deletion is available through detail toolbar, swipe and context actions with a confirmation explaining balance reversal and photo removal. Account deletion opens an impact sheet with record/transfer counts, balance, Keep/Delete Records strategy and a final destructive confirmation. Category deletion offers child reassignment or deletion and explains the Uncategorized fallback. Disable actions while saving and retain forms with inline errors on failure.

## Planning, Budgets and Reports

Planning is a native navigation list linking Budgets, Recurring, Bills and Reports. Budget progress rows show a name, textual limit status, progress bar, spent/available amounts, remaining/over-budget amount and optional rollover text. Values retain currency labels; red over-budget styling always has a textual status. Current progress appears in Planning, Statistics and category details. The budget comparison screen offers a date selector separate from its editable definitions.

Recurrence is an optional Repeat section in new record forms. Schedule editors show frequency, count and end-date controls; series detail separates future record details, schedule changes, pause/resume/cancel and upcoming occurrence actions. Saved and future occurrence editing reuse the existing record editor, including amount, category, account, details and photos. Cancel Series requires confirmation and retains saved records.

Bill rows show name, currency amount, due/overdue text, Mark as Paid and Edit. Calendar mode uses a graphical date picker and a day-filtered list of next unpaid bills. Payment confirmation distinguishes expense creation from marking paid only; a linked account and category are required for expense creation. Deletion preserves previously created payment records. Editors retain input and inline errors on failed saves; notification permission failures appear in the active editor.

Reports use native period/account/currency controls and readable sectioned summaries/statements. Prepare PDF creates a labeled snapshot before showing Share PDF. PDF output uses A4 pages, 48-point side margins, repeated small headers/page numbers, 22-point titles, 14-point section headings and 11-point body text. CoreText wraps long notes and paginates without clipping. Export does not include receipt images.
