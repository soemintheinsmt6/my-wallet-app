import PhotosUI
import SwiftUI
import WalletDomain

struct RecordEditorView: View {
    @ObservedObject var viewModel: RecordsViewModel
    let record: WalletRecord?
    let saveAction: ((UUID, RecordDraft) async throws -> Void)?
    let editorTitle: String?
    let allowsRecurrence: Bool
    @State private var isSubmitting = false
    private var isBusy: Bool { viewModel.isSaving || isSubmitting }
    @State private var originalPhotoLoaded: Bool
    @State private var isLoadingOriginalPhoto = false
    @Environment(\.dismiss) private var dismiss
    @State private var draft = RecordDraft()
    @State private var recordID = UUID()
    @State private var amount = ""
    @State private var receivedAmount = ""
    /// Empty means "use the downloaded rate"; the draft keeps `nil` in that case.
    @State private var manualRate = ""
    @Environment(\.currencyViewModel) private var currencyModel
    @State private var selectingCategory = false
    @State private var selectingTags = false
    @State private var photoItem: PhotosPickerItem?
    @State private var isLoadingPhoto = false
    @State private var errorMessage: String?
    @AppStorage(WalletPreferenceKeys.lastUsedAccountID) private var lastUsedAccountID = ""
    @AppStorage(WalletPreferenceKeys.lastUsedPaymentType) private var lastUsedPaymentType = PaymentType.unspecified.rawValue
    @FocusState private var focusedField: InputField?
    private enum InputField: Hashable { case amount, receivedAmount, note, payee }
    @State private var didFocusAmount = false
    @State private var selectionScreen: SelectionScreen?
    private enum SelectionScreen: String, Hashable { case account, destination, payment }

    /// `initialKind` preselects the segmented type for a new record; widget quick-add uses it.
    init(viewModel: RecordsViewModel, record: WalletRecord? = nil, title: String? = nil, allowsRecurrence: Bool = true, initialKind: RecordKind? = nil, saveAction: ((UUID, RecordDraft) async throws -> Void)? = nil) {
        self.viewModel = viewModel
        self.record = record
        self.saveAction = saveAction
        self.editorTitle = title
        self.allowsRecurrence = allowsRecurrence
        var initialDraft = record?.draft ?? RecordDraft()
        if record == nil, let initialKind { initialDraft.kind = initialKind }
        _draft = State(initialValue: initialDraft)
        _recordID = State(initialValue: record?.id ?? UUID())
        _amount = State(initialValue: record.map { AccountAmountInput.text($0.draft.amount) } ?? "")
        _receivedAmount = State(initialValue: record?.draft.receivedAmount.map { AccountAmountInput.text($0) } ?? "")
        _manualRate = State(initialValue: record?.draft.manualRate.map { AccountAmountInput.text($0) } ?? "")
        _originalPhotoLoaded = State(initialValue: record?.hasPhoto != true)
    }

    private var canSave: Bool {
        guard originalPhotoLoaded, !isBusy, !isLoadingPhoto,
            let value = try? AccountAmountInput.parse(amount)
        else { return false }
        var values = draft
        values.amount = value
        if crossCurrency {
            guard let received = try? AccountAmountInput.parse(receivedAmount) else { return false }
            values.receivedAmount = received
        }
        return (try? values.validate(allowUncategorized: record != nil)) != nil
    }

    private var currency: String { viewModel.account(draft.accountID)?.currencyCode ?? "" }
    private var destinationCurrency: String { viewModel.account(draft.destinationAccountID)?.currencyCode ?? "" }
    private var crossCurrency: Bool {
        draft.kind == .transfer && !currency.isEmpty && !destinationCurrency.isEmpty && currency != destinationCurrency
    }
    private var selectedLabels: String {
        let names = viewModel.tags.filter { draft.tagIDs.contains($0.id) }.map(\.name)
        return names.isEmpty ? "None" : names.joined(separator: ", ")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    amountSection
                    generalSection
                    detailsSection
                    if record == nil && allowsRecurrence {
                        VStack(alignment: .leading, spacing: 12) {
                            RecurrenceFields(rule: $draft.recurrence, start: draft.date)
                            if draft.recurrence != nil {
                                Text("This record is saved now. Later occurrences are created when the app opens or becomes active. Manage them under Planning → Recurring.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(20)
                    }
                    if let errorMessage { Text(errorMessage).foregroundStyle(.red).padding(20) }
                }
                .background {
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { focusedField = nil }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .background {
                Color.clear.contentShape(Rectangle())
                    .onTapGesture { focusedField = nil }
            }
            .disabled(isBusy)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    Divider()
                    Button {
                        Task { await save() }
                    } label: {
                        HStack {
                            Spacer()
                            if isBusy { ProgressView() } else { Text("Save").font(.headline) }
                            Spacer()
                        }
                        .frame(minHeight: 28)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                }
                .background(.background)
            }
            .navigationTitle(editorTitle ?? (record == nil ? "Add Record" : "Edit Record"))
            #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isBusy)
                }
            }
            .sheet(isPresented: $selectingCategory) {
                RecordCategoryPicker(viewModel: viewModel, kind: draft.kind, selection: $draft.categoryID)
            }
            .sheet(isPresented: $selectingTags) { RecordTagPicker(viewModel: viewModel, selection: $draft.tagIDs) }
            .navigationDestination(item: $selectionScreen) { screen in
                switch screen {
                case .account:
                    RecordAccountSelection(
                        accounts: viewModel.accounts, selection: $draft.accountID,
                        title: draft.kind == .transfer ? "From account" : "Account")
                case .destination:
                    RecordAccountSelection(
                        accounts: viewModel.accounts.filter { $0.id != draft.accountID },
                        selection: $draft.destinationAccountID, title: "To account")
                case .payment:
                    RecordPaymentSelection(selection: $draft.paymentType)
                }
            }
            .task {
                guard !didFocusAmount else { return }
                didFocusAmount = true
                if record == nil, let id = UUID(uuidString: lastUsedAccountID), viewModel.account(id) != nil {
                    draft.accountID = id
                }
                if record == nil { draft.paymentType = PaymentType(rawValue: lastUsedPaymentType) ?? .unspecified }
                await loadOriginalPhoto()
                await Task.yield()
                focusedField = .amount
            }
            .interactiveDismissDisabled(isBusy)
            .task(id: photoItem) { await loadPhoto() }
            .onChange(of: draft.accountID) { _, id in
                if draft.destinationAccountID == id { draft.destinationAccountID = nil }
            }
        }
        #if os(macOS)
            .frame(minWidth: 540, minHeight: 720)
        #endif
    }

    @ViewBuilder
    private var amountSection: some View {
        VStack(spacing: 12) {
            Picker("Record type", selection: $draft.kind) {
                ForEach(RecordKind.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            RecordAmountField(
                kind: draft.kind, currency: currency, amount: $amount, focus: $focusedField, field: InputField.amount)
            if crossCurrency {
                HStack {
                    Text("Received \(destinationCurrency)")
                    TextField("0", text: $receivedAmount).multilineTextAlignment(.trailing).accessibilityLabel(
                        "Received amount"
                    )
                    .focused($focusedField, equals: .receivedAmount)
                }
                Text("Enter the actual amount received. No exchange rate is assumed.").font(.caption).foregroundStyle(
                    .secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var generalSection: some View {
        sectionHeader("General")
        recordRow("wallet.bifold.fill", color: .blue, filledIcon: true) {
            selectionButton(
                draft.kind == .transfer ? "From account" : "Account", value: viewModel.account(draft.accountID)?.name,
                screen: .account)
        }
        if draft.kind == .transfer {
            recordRow("wallet.bifold.fill", color: .blue, filledIcon: true) {
                selectionButton(
                    "To account", value: viewModel.account(draft.destinationAccountID)?.name, screen: .destination)
            }
        }
        recordRow(
            viewModel.category(draft.categoryID)?.symbol ?? "questionmark",
            color: viewModel.category(draft.categoryID)?.colorToken.color ?? .gray, categoryTile: true
        ) {
            Button {
                selectingCategory = true
            } label: {
                HStack {
                    Text("Category").foregroundStyle(.primary)
                    Spacer()
                    Text(
                        draft.categoryID == nil
                            ? (draft.kind == .transfer ? "Optional" : (record == nil ? "Required" : "Uncategorized"))
                            : viewModel.categoryTitle(draft.categoryID)
                    )
                    .foregroundStyle(draft.categoryID == nil && draft.kind != .transfer ? Color.red : Color.secondary)
                    chevron
                }
            }
            .buttonStyle(.plain)
        }
        let frequent = viewModel.mostUsedCategories(for: draft.kind)
        if !frequent.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Most used").font(.caption).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(frequent) { category in
                            Button {
                                draft.categoryID = category.id
                            } label: {
                                Label(category.name, systemImage: category.symbol)
                            }
                            .buttonStyle(.bordered)
                            .tint(category.colorToken.color)
                            .accessibilityLabel(viewModel.categoryTitle(category.id))
                            .accessibilityAddTraits(draft.categoryID == category.id ? .isSelected : [])
                        }
                    }
                }
            }
            .padding(20)
        }
        recordRow("calendar") {
            RecordDateTimeField(date: $draft.date) { focusedField = nil }
        }
        recordRow("tag") {
            Button {
                selectingTags = true
            } label: {
                HStack {
                    Text("Labels").foregroundStyle(.primary)
                    Spacer()
                    if !draft.tagIDs.isEmpty { Text(selectedLabels).foregroundStyle(.secondary) }
                    Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(.blue)
                }
            }.buttonStyle(.plain)
        }
    }

    /// Lets the user pin the rate used to convert this record into the home currency.
    ///
    /// Only shown when converted totals are switched on and this record is not already in the home
    /// currency; otherwise there is nothing to convert and the row would only add noise.
    @ViewBuilder private var exchangeRateRow: some View {
        if let currencyModel, currencyModel.convertsTotals, !currency.isEmpty,
           currency != currencyModel.homeCurrency {
            recordRow("arrow.left.arrow.right") {
                Text("Rate to \(currencyModel.homeCurrency)")
                TextField(marketRatePlaceholder, text: $manualRate)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .accessibilityLabel("Exchange rate to \(currencyModel.homeCurrency)")
                    #if os(iOS)
                        .keyboardType(.decimalPad)
                    #endif
            }
            Text("Leave empty to use the downloaded rate. One \(currency) is worth this many \(currencyModel.homeCurrency).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, WalletMetrics.xLarge)
                .padding(.bottom, WalletMetrics.small)
        }
    }

    /// Shows today's market rate as the placeholder, so a manual entry has something to start from.
    private var marketRatePlaceholder: String {
        guard let currencyModel, let rates = currencyModel.rates,
              let rate = try? CurrencyConverter.rate(from: currency, to: currencyModel.homeCurrency, using: rates)
        else { return "Market rate" }
        return AccountAmountInput.text(CurrencyConverter.rounded(rate, currencyCode: "XXX"))
    }

    @ViewBuilder
    private var detailsSection: some View {
        sectionHeader("More Details")
        recordRow("square.and.pencil") {
            TextField("Note", text: $draft.note, axis: .vertical).lineLimit(1...6)
                .focused($focusedField, equals: .note)
        }
        recordRow("person") {
            Text("Payee")
            TextField("Optional", text: $draft.payee).multilineTextAlignment(.trailing).accessibilityLabel("Payee")
                .focused($focusedField, equals: .payee)
        }
        recordRow("creditcard") {
            selectionButton(
                "Payment type", value: draft.paymentType == .unspecified ? nil : draft.paymentType.title,
                screen: .payment)
        }
        exchangeRateRow
        if !originalPhotoLoaded {
            if isLoadingOriginalPhoto { ProgressView("Loading existing photo…") }
            else { Button("Retry Loading Existing Photo") { Task { await loadOriginalPhoto() } } }
        }
        let photoTitle = draft.photoData == nil ? "Attach Photo" : "Replace Photo"
        recordRow("photo") {
            PhotosPicker(selection: $photoItem, matching: .images) {
                Text(photoTitle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .disabled(!originalPhotoLoaded)
        if isLoadingPhoto { ProgressView("Preparing photo…") }
        if let data = draft.photoData {
            RecordPhotoView(data: data)
            Button("Remove Photo", role: .destructive) {
                draft.photoData = nil
                photoItem = nil
            }
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 30)
            .padding(.bottom, 16)
            .background(.quaternary.opacity(0.35))
            .contentShape(Rectangle())
            .onTapGesture { focusedField = nil }
            .accessibilityAddTraits(.isHeader)
    }

    private func selectionButton(_ title: String, value: String?, screen: SelectionScreen) -> some View {
        Button {
            focusedField = nil
            selectionScreen = screen
        } label: {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                if let value { Text(value).foregroundStyle(.secondary) }
                chevron
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func recordRow<Content: View>(
        _ symbol: String, color: Color = .gray, categoryTile: Bool = false, filledIcon: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        RecordFormRow(
            symbol: symbol, color: color, category: viewModel.category(draft.categoryID), categoryTile: categoryTile,
            filledIcon: filledIcon, content: content)
    }

    private func loadOriginalPhoto() async {
        guard !originalPhotoLoaded, !isLoadingOriginalPhoto, let record else { return }
        isLoadingOriginalPhoto = true
        defer { isLoadingOriginalPhoto = false }
        do {
            guard let data = try await viewModel.photo(id: record.id) else {
                throw RecordValidationError.invalidPhoto
            }
            draft.photoData = data
            originalPhotoLoaded = true
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    private func loadPhoto() async {
        guard let item = photoItem else {
            isLoadingPhoto = false
            return
        }
        isLoadingPhoto = true
        defer { if item == photoItem { isLoadingPhoto = false } }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw RecordValidationError.invalidPhoto
            }
            let prepared = try await Task.detached { try RecordPhoto.prepare(data) }.value
            try Task.checkCancellation()
            if item == photoItem { draft.photoData = prepared }
        } catch is CancellationError {
        } catch { if item == photoItem { errorMessage = error.localizedDescription } }
    }

    private func save() async {
        guard canSave else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        errorMessage = nil
        do {
            var values = draft
            values.amount = try AccountAmountInput.parse(amount)
            values.receivedAmount = crossCurrency ? try AccountAmountInput.parse(receivedAmount) : nil
            // An empty rate field means "use the downloaded rate", stored as no override at all.
            values.manualRate = manualRate.trimmingCharacters(in: .whitespaces).isEmpty
                ? nil : try AccountAmountInput.parse(manualRate)
            if let saveAction { try await saveAction(recordID, values) }
            else { try await viewModel.save(id: recordID, draft: values, editing: record != nil) }
            lastUsedAccountID = values.accountID?.uuidString ?? ""
            lastUsedPaymentType = values.paymentType.rawValue
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}
