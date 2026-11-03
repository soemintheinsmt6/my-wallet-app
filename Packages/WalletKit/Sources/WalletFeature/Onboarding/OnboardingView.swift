import SwiftUI
import WalletDomain

/// First-launch setup. Shown in place of the tabs until it is completed or skipped.
public struct OnboardingView: View {
    @ObservedObject private var viewModel: OnboardingViewModel
    @ObservedObject private var categories: CategoriesViewModel
    @State private var isChoosingCurrency = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case name, balance, budgetName, budgetAmount }

    public init(viewModel: OnboardingViewModel, categories: CategoriesViewModel) {
        self.viewModel = viewModel
        self.categories = categories
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                content
                    .padding(.horizontal, WalletMetrics.xLarge)
                    .padding(.bottom, WalletMetrics.xLarge)
            }
            .scrollDismissesKeyboard(.interactively)
            footer
        }
        .background(.background)
        .task { await categories.observe() }
        .sheet(isPresented: $isChoosingCurrency) {
            CurrencyPickerView(selection: $viewModel.currencyCode)
        }
    }

    // MARK: - Chrome

    private var header: some View {
        VStack(spacing: WalletMetrics.medium) {
            HStack {
                if viewModel.canGoBack {
                    Button("Back") { viewModel.back() }
                        .font(.subheadline)
                }
                Spacer()
                if !viewModel.isLastStep {
                    Button("Skip") { viewModel.skip() }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(value: Double(viewModel.step.rawValue + 1),
                         total: Double(OnboardingViewModel.Step.allCases.count))
                .accessibilityLabel("Step \(viewModel.step.rawValue + 1) of \(OnboardingViewModel.Step.allCases.count)")
        }
        .padding(.horizontal, WalletMetrics.xLarge)
        .padding(.top, WalletMetrics.medium)
        .padding(.bottom, WalletMetrics.large)
    }

    private var footer: some View {
        VStack(spacing: WalletMetrics.small) {
            if let message = viewModel.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            Button {
                focusedField = nil
                Task { await viewModel.advance() }
            } label: {
                HStack {
                    Spacer()
                    if viewModel.isSaving { ProgressView() } else { Text(primaryTitle).font(.headline) }
                    Spacer()
                }
                .frame(minHeight: 28)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!viewModel.canAdvance)
        }
        .padding(WalletMetrics.xLarge)
        .background(.background)
    }

    private var primaryTitle: String {
        switch viewModel.step {
        case .welcome: "Get Started"
        case .account: "Create Account"
        case .categories: "Continue"
        case .budget: viewModel.wantsBudget ? "Create Budget" : "Skip Budget"
        case .ready: "Start Using My Wallet"
        }
    }

    // MARK: - Steps

    @ViewBuilder private var content: some View {
        switch viewModel.step {
        case .welcome: welcome
        case .account: account
        case .categories: categoriesStep
        case .budget: budget
        case .ready: ready
        }
    }

    private func title(_ text: String, _ subtitle: String, symbol: String) -> some View {
        VStack(spacing: WalletMetrics.medium) {
            Image(systemName: symbol)
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text(text)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, WalletMetrics.large)
        .accessibilityElement(children: .combine)
    }

    private var welcome: some View {
        VStack(spacing: WalletMetrics.large) {
            title("Welcome to My Wallet",
                  "Track what you earn and spend, across every account you use.",
                  symbol: WalletSymbols.wallet)
            VStack(spacing: WalletMetrics.large) {
                point("Every account in one place", "Cash, cards, savings and loans, each in its own currency.",
                      symbol: "creditcard", tint: .blue)
                point("See where the money goes", "Charts by category, spending trends and balance history.",
                      symbol: "chart.pie", tint: .orange)
                point("Stay ahead of the month", "Budgets, recurring records and bill reminders.",
                      symbol: "calendar.badge.clock", tint: .green)
                point("Private by default", "Your wallet syncs through your own iCloud account. No one else sees it.",
                      symbol: "lock", tint: .indigo)
            }
        }
    }

    private func point(_ heading: String, _ detail: String, symbol: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: WalletMetrics.large) {
            WalletIconTile(symbol: symbol, color: tint, large: true)
            VStack(alignment: .leading, spacing: WalletMetrics.tight) {
                Text(heading).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var account: some View {
        VStack(spacing: WalletMetrics.large) {
            title("Add your first account",
                  "An account holds a balance — your cash, a card or a savings account.",
                  symbol: "building.columns")

            VStack(spacing: WalletMetrics.medium) {
                field("Name") {
                    TextField("Everyday Cash", text: $viewModel.accountName)
                        .focused($focusedField, equals: .name)
                        .textInputAutocapitalizationWords()
                }

                field("Type") {
                    Menu {
                        Picker("Type", selection: $viewModel.accountType) {
                            ForEach(AccountType.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    } label: {
                        HStack {
                            Text(viewModel.accountType.title).foregroundStyle(.primary)
                            WalletMenuIndicator()
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Type")
                    .accessibilityValue(viewModel.accountType.title)
                }

                field("Currency") {
                    Button { isChoosingCurrency = true } label: {
                        HStack {
                            Text(viewModel.currencyCode).foregroundStyle(.primary)
                            WalletDisclosure()
                        }
                    }
                }

                field("Starting balance") {
                    WalletAmountField(amount: viewModel.startingBalance) {
                        TextField("", text: $viewModel.startingBalance.groupedAmount())
                            .focused($focusedField, equals: .balance)
                            #if os(iOS)
                                .keyboardType(.decimalPad)
                            #endif
                    }
                    .monospacedDigit()
                }
            }

            Text("The currency cannot be changed after the account is created. You can add more accounts at any time.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var categoriesStep: some View {
        VStack(spacing: WalletMetrics.large) {
            title("Categories are ready",
                  "Every record is filed under a category, so your charts mean something. These are set up for you.",
                  symbol: "folder")

            let roots = Array(categories.rootCategories.prefix(8))
            if roots.isEmpty {
                ProgressView("Preparing categories…")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: WalletMetrics.medium)],
                          spacing: WalletMetrics.medium) {
                    ForEach(roots) { category in
                        HStack(spacing: WalletMetrics.small) {
                            CategoryIcon(category: category)
                            Text(category.name)
                                .font(.subheadline)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(WalletMetrics.small)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: WalletMetrics.medium, style: .continuous))
                        .accessibilityElement(children: .combine)
                    }
                }
                Text("Rename them, add your own, or split them into subcategories under the Categories screen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var budget: some View {
        VStack(spacing: WalletMetrics.large) {
            title("Set a monthly budget?",
                  "A budget tracks what you spend against a limit. This is optional — you can add budgets later.",
                  symbol: "chart.bar")

            Toggle("Create a monthly budget", isOn: $viewModel.wantsBudget.animation())
                .padding(.horizontal, WalletMetrics.tight)

            if viewModel.wantsBudget {
                VStack(spacing: WalletMetrics.medium) {
                    field("Name") {
                        TextField("Monthly Spending", text: $viewModel.budgetName)
                            .focused($focusedField, equals: .budgetName)
                    }
                    field("Limit (\(viewModel.currencyCode))") {
                        WalletAmountField(amount: viewModel.budgetAmount) {
                            TextField("", text: $viewModel.budgetAmount.groupedAmount())
                                .focused($focusedField, equals: .budgetAmount)
                                #if os(iOS)
                                    .keyboardType(.decimalPad)
                                #endif
                        }
                        .monospacedDigit()
                    }
                }
                Text("This covers spending across all categories in \(viewModel.currencyCode), starting today.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var ready: some View {
        VStack(spacing: WalletMetrics.large) {
            title("You're set up",
                  "Add your first record from Dashboard or the Records tab whenever you're ready.",
                  symbol: "checkmark.circle")
            VStack(spacing: WalletMetrics.large) {
                point("Dashboard", "Your balance, this month and recent activity at a glance.",
                      symbol: "square.grid.2x2", tint: .blue)
                point("Records", "Add expenses, income and transfers; search and filter them.",
                      symbol: "list.bullet.rectangle", tint: .orange)
                point("More", "Accounts, categories, labels and settings live here.",
                      symbol: "ellipsis.circle", tint: .gray)
            }
        }
    }

    /// A labelled row matching the record editor's leading-label, trailing-value rhythm.
    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: WalletMetrics.large)
            content()
        }
        .frame(minHeight: WalletMetrics.touchTarget)
        .padding(.horizontal, WalletMetrics.large)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: WalletMetrics.medium, style: .continuous))
    }
}

private extension View {
    /// `textInputAutocapitalization` is iOS-only; this keeps the call sites free of `#if`.
    @ViewBuilder func textInputAutocapitalizationWords() -> some View {
        #if os(iOS)
            self.textInputAutocapitalization(.words)
        #else
            self
        #endif
    }
}
