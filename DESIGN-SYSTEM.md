# Design System

[README](README.md) · [Architecture](ARCHITECTURE.md) · [Testing](TESTING.md)

## Current Foundation

The app uses native SwiftUI navigation, lists, grouped forms, sheets and semantic colors. Shared tokens and components live in `Sources/WalletFeature/Shared/DesignSystem/`; screens compose them rather than repeating literals.

Use system controls and text styles for new screens. Keep account-specific color independent of global action tint. `Assets.xcassets` contains app icon and accent-color slots; the accent asset currently has no custom color components.

### Shared tokens and components

| Type | Purpose |
| --- | --- |
| `WalletMetrics` | 4-point spacing scale (`hair` 2 … `xxLarge` 28), `touchTarget` 44, `Tile` sizes, `Chart` heights |
| `WalletIconTile` | The one leading-icon treatment: white medium-weight symbol on a gradient color tile, 36 pt standard / 44 pt `large`; category, account, record-kind and menu icons all draw through it |
| `WalletDisclosure` | Trailing right chevron matching the system's `NavigationLink` weight, for any row that opens something, by push or by sheet |
| `WalletMenuIndicator` | Trailing up-and-down chevrons at the same weight, for rows that open a menu in place |
| `WalletClipboard.copySensitive(_:)` | Copies text that should not linger, such as an account number: local to the device and expiring after a minute on iOS |
| `WalletMenuPicker` | A form row that opens a menu of options: title, the current value in secondary text, and `WalletMenuIndicator`; only the value and chevrons are the menu, so the title never fades when tapped |
| `WalletAmountText` | Money with the sign and tint rules; `.net(_:currencyCode:)` signs from the value itself |
| `WalletStatTile` | Labelled figure for summary rows, on a cleared list row so the grouped background reads as the gap |
| `WalletBadge` | Status capsule; the label always carries the meaning |
| `WalletEmptyState` / `WalletLoadingState` | The single empty and loading shapes, wrapping `ContentUnavailableView` and `ProgressView` |
| `WalletLaunchView` | The launch screen: wallet mark, app name and a quiet progress line on the grouped background; shown while storage opens and during the dashboard's first load |
| `WalletListFooter` / `.walletFirstRow(_:)` | Caption-style section footers for flat lists, and hiding the stray rule above a flat list's first row |
| `Color.walletCard` / `Color.walletGroupedBackground` | The grouped list's card fill and background, for tiles placed on cleared rows and full screens; correct in dark mode, unlike `.background` |
| `Decimal.walletFormatted(_:)` | The app-wide money format: account currency, up to eight fractional digits |

Prefer these over literals so unrelated screens line up. The trailing glyph says what a tap does: a right chevron means the row opens something, whether it pushes a screen or presents a sheet, full-screen cover or dialog (list rows that open an editor, Icon, Currency, Passcode, Split with people, Photo, receipts), and up-and-down chevrons open a menu where the row is, as on every `WalletMenuPicker` row and the Dashboard and Statistics currency menus. Use `WalletMenuPicker` rather than a bare menu-style `Picker`, whose value takes the accent color instead of the secondary text other rows use. `CategoryIcon` adds the category's chosen symbol and color, then draws through `WalletIconTile`.

### List styles

Long lists of like items use the flat (plain) style, rows edge to edge: Records, Accounts, Categories, Labels, Splits, Recurring, Bills, Debts, Drinking Days and the account, currency, payment type and label pickers. Editors, Settings, filters, More and dashboards keep the inset grouped style, where cards group related controls. In a flat list, footers use `WalletListFooter` (plain lists otherwise draw them at body size), controls above the rows (segmented pickers, date pickers) hide their separators, and a list that starts without a header hides its first row's top rule.

## Navigation

Five tabs: Dashboard, Records, Statistics, Planning and More. iOS collapses anything past five into its own "More" list, so the secondary destinations live behind `MoreView`, where Accounts, Categories, Labels and Settings keep real icon tiles, counts and a badge when an account balance limit is breached. `WalletTab` in `Shared/Navigation/` is the shared tab identity; `HomeView` takes a binding to it so dashboard sections can link through to the tab that owns them.

Dashboard, Records, Statistics and Planning each own a `NavigationStack`. Screens reached through More do not; they are pushed into the More stack and only declare their title, toolbar and destinations.

`HomeView` (the Dashboard tab, `square.grid.2x2`) is derived entirely from the other view models; its only persistence is the card arrangement. It always covers the current month across every account included in statistics, with no period or account scope of its own. Cards: total balance for the dominant currency (account count and currency trailing the label, a currency menu only when several are in use, and a tinted chip with this month's net), a two-column grid of compact account cards (icon beside "Name · currency" and the balance) with an Add tile, quick actions, this month's income and expenses, Balance Trend, Expenses by category or label, Top Expenses, budgets, goals, bills and recent records. Tiles placed on cleared rows use `Color.walletCard` so they match the cards around them in dark mode. Tapping an account card opens `AccountDetailView`, which owns the per-account and per-period view.

## Color and Typography

`AccountColor+Presentation.swift` maps ten stored choices to SwiftUI colors: blue, teal, green, yellow, orange, red, pink, purple, indigo and gray. Account icons use white symbols on gradient tiles in the chosen color, matching category icons. Color choices include a name and selection checkmark. The read-only category editor swatch is labeled Color.

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

Label rows use 36-point solid-color tiles with 18-point white tag symbols, a name and a trailing chevron, since a tap opens the editor as a sheet; row content stays at least 44 points tall. The shared label editor uses a leading Name label, trailing-aligned text field, and the same ten-color grid pattern as accounts. Titles are Create Label and Edit. A destructive Delete Label action requires confirmation; deletion is also available through swipe/context actions. Preserve the draft and show inline errors when saving or deletion fails. The macOS label editor minimum is 440 × 460 points.

Each tab has its own navigation stack. `CategoriesView` displays root names and relevant SF Symbols without subcategory counts or nature chips. `WalletCategory+Presentation` maps all 60 starter IDs to icons, preserving icons after renaming. Custom children fall back to their seeded parent's icon; other custom items use a tag. `CategoryDetailView` shows its card below the navigation title without a large header icon. Category and subcategory names share a horizontal row with their nature chips. Subcategory rows retain icons, use a trailing chevron and open the editor. Edit Category and Create Subcategory remain explicit actions.

## Record Components

Record UI sources live in `Sources/WalletFeature/Records/`. `RecordAmountField` owns amount presentation, `RecordDateTimeField` owns the date popover, and `RecordFormRow` centralizes row geometry. `RecordEditorView` keeps draft/focus/navigation state and composes these controls; reuse the extracted components instead of copying their layout.

Date & Time uses primary-colored, trailing, locale-aware date/time text with relative day labels and no capsule background. The row opens a native graphical date/time picker in a popover without Done; changes update the draft immediately and tapping outside dismisses it.

The amount header uses a 60-point Dynamic Type-scaled font, 12-point stack spacing and 4-point vertical amount padding. Currency is a subheadline pill with 12 × 6-point padding. Save is a full-width pill (`.borderedProminent`, capsule shape, large control size) with a 28-point minimum label height and a 10-point vertical footer margin; the pill matches the segmented selector and currency capsule above it. Expense amounts use the system red, aligned with every other expense red. When the record is in another currency and converted totals are on, a "≈ amount" line under the amount shows it in the main currency as the amount, account or rate changes; a cross-currency transfer also states its currency gain or loss. Blank-background/section-header taps clear focus for all entry text fields without adding a tap gesture to interactive controls.

Display locale-aware grouping in the main amount, preserving fractional zeros and incomplete decimal input. Account rows use a fixed white wallet on blue, independent of selection. New drafts restore the locally last-saved account/payment type; persist defaults only after a successful save.

All record-row leading icons, including Attach Photo, use 18-point symbols in 36 × 36-point slots, with a 10-point text gap and aligned dividers. Account icons use fixed white wallet symbols on blue with 10-point rounded corners, matching category tiles. The amount input uses clear tint to hide its insertion cursor while retaining focus and keyboard input.

Focus the amount once on initial presentation, not again after returning from selection. Hide the currency capsule without a selected account. Account and Payment Type rows have leading labels, optional trailing values and chevrons; push selection lists with checkmarks and return after choosing. Transfer destination excludes the source account. Reuse `CategoryIcon` for selected categories and a gray white-symbol tile when unselected.

Use an inline Add Record navigation title on mobile. A segmented selector sits above a left currency capsule and right-aligned amount using a Dynamic Type-scaled 60-point regular font with monospaced digits. Expense amounts have a red minus prefix, income amounts a green plus, and transfers use primary text without a prefix. Keep signs outside the stored value. Full-width rows use 36-point leading icon slots, inset dividers and muted section-header bands. A safe-area bottom Save button remains disabled until required input is valid. Missing required categories display Required in red. The Label row's icon takes the chosen label's color and filled tag symbol. Selection rows end in a chevron, both those that push a list and Split with people and Photo, which open a sheet or dialog. Editing a saved record adds a Delete Record row at the end, laid out like the other rows (red trash icon, leading title) and confirmed before deleting.

Record creation uses an Expense/Income/Transfer segmented selector and amount input. General groups account (From/To for transfers), category, most-used shortcuts, date/time and labels. More Details groups optional note, payee, payment type and library-photo attachment. Different-currency transfers reveal a received amount input.

The searchable category sheet allows either a root or child selection and reuses fixed category colors/icons; most-used entries include parent context. A record takes one label: the label picker lists No label and every label, and choosing one returns to the form. Photo loading shows progress and disables saving; previews offer replacement/removal. Record rows end in a chevron after the amount, in the Records list, the Dashboard's recent records and an account's activity; tapping one opens the record form directly (there is no separate details screen); the form loads original photos before permitting saves and carries the receipt gallery and converted amount the details screen used to show. Closing a new record without saving removes any split or scanned receipts already made for it. Categories are shown by their own name everywhere, never "Parent / Child"; only CSV export and Shortcuts keep the full path. Retain textual type labels alongside red expense, green income and blue transfer indicators.

The records list groups rows into day sections with a Today/Yesterday/weekday header and the day's net on the trailing edge. `RecordDayGrouping` owns that logic: transfers are excluded from the net exactly as statistics excludes them, and a day spanning more than one currency states no net rather than adding unlike currencies. Day headers appear in date order and for search results: results ranked by relevance are regrouped with the newest day first and the best match first within each day, so the headers always run in date order. Sorting by amount drops the headers, since a size ranking would otherwise be scattered across days. A toolbar sort menu exposes the order.

`RecordRow` is the shared row for the ledger and the Dashboard: category tile, name, account/payee context with the time, and the trailing signed amount. Rows without a category fall back to a kind-colored tile.

The records list uses the native search field with a prompt naming the searched fields, and recent searches appear as a labeled suggestion section with a clear action. The toolbar filter control uses `line.3.horizontal.decrease.circle`, filled while filters are active, and carries an accessibility value naming the number of active filters. An active search or filter shows a leading footnote summary row with a Clear action; empty results use `ContentUnavailableView` naming the search text and offering the same clear action rather than replacing the "No records yet" state.

`RecordFilterView` is a grouped form that edits a private copy of the query and applies on Apply, so Cancel leaves visible results unchanged. It reuses record-row checkmark selection with 44-point minimum rows, pushes long lists (categories, payment types) instead of inlining them, states its selection counts in trailing values, and disables Apply while an amount bound is invalid. Footers explain transfer, subcategory and currency behavior; Clear All Filters is destructive and disabled when nothing is set.

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
| Other | `wallet.bifold` (`wallet.pass` before iOS 18 / macOS 15) |

These are defaults. An account may choose its own symbol from the shared symbol picker (the Icon row in the account editor); the choice is part of `AccountSettings.symbol` and syncs with the account. The picker (`WalletSymbolPicker`, shared with category icons) offers a curated `CategorySymbolCatalog` of 189 symbols in titled groups (Food & Drink, Shopping, Home, Bills & Utilities, Transport, Health & Fitness, Fun & Learning, Tech, Money, People & Pets, Travel, Other); search matches symbol names and group titles. Only symbols available on iOS 17 and macOS 14 are offered, since a newer one renders as a blank tile there. The app's own wallet mark (launch view, Balance card, More, empty states, onboarding, widgets and complications) comes from `WalletSymbols.wallet`/`walletFill` in `WalletDomain`, which use `wallet.bifold` on iOS 18, macOS 15, watchOS 11 and visionOS 2 and fall back to `wallet.pass` earlier. The Show Balance App Shortcut uses `wallet.pass` directly, because App Shortcut icons must be string literals. Without one, the type decides the icon, so changing the type still changes it. Read `account.symbol` rather than `account.type.symbol` wherever an account is drawn.

## Interaction and Content

Disable form editing, cancellation and interactive dismissal while saving. Preserve drafts after validation/storage errors. Use concise recovery messages. Account-list loading errors use an alert; save errors appear inline.

Display balances with the account currency and up to eight fractional digits. Input accepts the local decimal separator without grouping. Explain currency immutability and notification behavior in form footers. In-app balance notices use `bell.badge` and text identifying the breached limit.

## Settings

Settings is reached through More, with a native System/Light/Dark segmented selector and an About section carrying the version and sync method.

A Privacy & Security section holds app lock: a Lock with Face ID toggle offered before any passcode exists, a Require Passcode toggle, the passcode length, a biometric toggle named for the device's own sensor (Face ID, Touch ID or Optic ID), and an Auto-Lock picker. Every control names the device's own sensor rather than saying "biometrics", and only the first, plainest one carries no icon. Auto-Lock and relaunching are the only ways the app re-locks; there is no Lock Now, because a button that puts the lock screen up is a step nobody takes deliberately. Setting, changing and removing a passcode all run through the same sheet, which steps through current/new/confirm prompts using the shared `PasscodeKeypad` and `PasscodeDots`. The lock screen fills the window, offers biometrics on appearance with the keypad always available, shakes the dots on a wrong entry (honoring Reduce Motion) and states the remaining delay in text while throttled. A lock held by biometrics alone drops the dots and keypad for a single prominent unlock button, since there is nothing to type. Theme is applied at the app root so sheets and all tabs share the same choice. Use semantic colors for surfaces and text.

Debug-only Temporary Development Tools contains a destructive Reset Wallet Data action and an explicit warning about iCloud propagation. Require confirmation, disable the tab interface during reset, show progress/errors, and discard open drafts after success. No reset action is visible in release builds.

## Accessibility and Review

Retain semantic text styles, readable labels, selected-state traits and explicit edit hints. Support keyboard interaction, larger text, light/dark appearance and adequate touch targets. Verify contrast for every swatch and avoid truncating essential amounts. These are review requirements; current automated tests do not establish accessibility or visual compliance.

Update this guide when adding shared visual conventions, and update [README.md](README.md) when the related feature is completed.

## Statistics and Destructive Actions

Statistics leads with a segmented Week/Month/Year/Custom control and a period stepper that moves whole periods with the range named between the arrows; stepping forward stops at the current period. Account, category, label and currency filters open a filter sheet (`StatisticsFilterView`) rather than a menu, since a flat menu of every category grew too long: checkmark rows for currency, account and label, and a searchable category list grouped by parent that returns on choosing. The sheet edits a private copy and applies on Apply. A summary row and Clear action appear only while a filter is set. The period summary is the shared `WalletSummaryCard` (signed net, the income/expense split bar, both totals), opening in the main currency when an account holds it, with a currency menu in the section header only when several currencies are in use. Below a divider it adds what was spent per day so far and spending against the same days of the previous period, worded as "12% more" or "12% less" with an arrow, red when spending rose and green when it fell, so the change never depends on color alone. The Dashboard uses the same card without those two figures.

Donut breakdowns hide the chart legend and carry the period total in the center as a short figure over its unit ("52.7" over "lakhs · MMK"), counted in lakhs or millions per the Count Large Amounts In setting, with each category listed below as color, name, share percentage and amount. The spending chart uses rounded bars over the selected granularity, the balance history a smooth monotone line with a soft area fill (the same curve as the Dashboard's Balance Trend, which never overshoots the real balances between points), and both use compact leading axis labels, counted like the donut total ("50L" in lakhs, "5M" in millions). Top spending categories are ranked with a proportional meter tinted by the category color. Charts remain decorative: every figure is stated in text beside them.

Accounts lead with a per-currency total as a header (no separators, large title amount, the explanation as a caption), then one list ordered by type and name with the type as each row's subtitle (omitted when it would repeat the name), followed by the masked account number (`•••• 1234`) when there is one, and the balance on the trailing edge; `AccountDetailView` shows one account's balance, its income and expenses for today, the week, month or year with arrows to earlier periods, and the records that touched it; the alert section uses `bell.badge` on red and states which limit was breached. Chart marks and legends reuse category color tokens with a gray Uncategorized fallback; names and amounts accompany color. VoiceOver marks expose dates/categories and formatted amounts. Empty periods show explicit no-activity text. Totals remain separate by currency and the history explanation stays visible.

Record deletion is available through detail toolbar, swipe and context actions with a confirmation explaining balance reversal and photo removal. Account deletion opens an impact sheet with record/transfer counts, balance, Keep/Delete Records strategy and a final destructive confirmation. It opens from the swipe and context actions in Accounts, or from a `WalletDestructiveRow` in its own section at the end of the account editor (editing only, never when creating). Deleting from the editor closes the impact sheet, then the editor, then the account's detail screen if the editor was opened there, one after another so presentations never dismiss at once. Category deletion offers child reassignment or deletion and explains the Uncategorized fallback. Disable actions while saving and retain forms with inline errors on failure.

## Planning, Budgets and Reports

Planning is a native navigation list linking Budgets, Recurring, Bills and Reports. Budget progress rows show a name, textual limit status, progress bar, spent/available amounts, remaining/over-budget amount and optional rollover text. Values retain currency labels; red over-budget styling always has a textual status. Current progress appears in Planning, Statistics and category details. The budget comparison screen offers a date selector separate from its editable definitions.

Recurrence is an optional Repeat section in new record forms. Schedule editors show frequency, count and end-date controls; series detail separates future record details, schedule changes, pause/resume/cancel and upcoming occurrence actions. Saved and future occurrence editing reuse the existing record editor, including amount, category, account, details and photos. Cancel Series requires confirmation and retains saved records.

Bill rows show name, currency amount, due/overdue text, Mark as Paid and Edit. Calendar mode uses a graphical date picker and a day-filtered list of next unpaid bills. Payment confirmation distinguishes expense creation from marking paid only; a linked account and category are required for expense creation. Deletion preserves previously created payment records. Editors retain input and inline errors on failed saves; notification permission failures appear in the active editor.

Reports use native period/account/currency controls and readable sectioned summaries/statements. Monthly and yearly reports pick their period with the same `WalletPeriodStepper` as Statistics (`‹ November 2026 ›`, forward stopping at the current period) rather than a "date in period" picker. The financial summary uses `WalletSummaryCard` with the same per-day and previous-period figures as Statistics, and the PDF states both in words. Prepare PDF creates a labeled snapshot before showing Share PDF. PDF output uses A4 pages, 48-point side margins, repeated small headers/page numbers, 22-point titles, 14-point section headings and 11-point body text. CoreText wraps long notes and paginates without clipping. Export does not include receipt images.
