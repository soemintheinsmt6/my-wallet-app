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
    @Environment(\.receiptUseCases) private var receiptUseCases
    @Environment(\.splitsViewModel) private var splitsViewModel
    @State private var isSplitting = false
    @State private var photoItem: PhotosPickerItem?
    @State private var isLoadingPhoto = false
    @State private var choosingPhotoSource = false
    @State private var pickingPhotoFromLibrary = false
    @State private var capturingPhoto = false
    @State private var viewingPhoto = false
    @State private var errorMessage: String?
    @AppStorage(WalletPreferenceKeys.lastUsedAccountID) private var lastUsedAccountID = ""
    @AppStorage(WalletPreferenceKeys.lastUsedPaymentType) private var lastUsedPaymentType = PaymentType.unspecified.rawValue
    @FocusState private var focusedField: InputField?
    private enum InputField: Hashable { case amount, receivedAmount }
    @State private var didFocusAmount = false
    @State private var selectionScreen: SelectionScreen?
    private enum SelectionScreen: String, Hashable { case account, destination, category, tags, payment, note, payee }

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
                    if record == nil && allowsRecurrence { recurrenceSection }
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
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                        .disabled(isBusy)
                }
            }
            .navigationDestination(item: $selectionScreen) { screen in
                switch screen {
                case .category:
                    RecordCategoryPicker(viewModel: viewModel, kind: draft.kind, selection: $draft.categoryID)
                case .tags:
                    RecordTagPicker(viewModel: viewModel, selection: $draft.tagIDs)
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
                case .note:
                    RecordTextEntry(title: "Note", text: $draft.note, caption: "Add note", multiline: true)
                case .payee:
                    RecordTextEntry(title: "Payee", text: $draft.payee, caption: "Add payee")
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
                    WalletAmountField(amount: receivedAmount) {
                        TextField("", text: $receivedAmount.groupedAmount())
                            .accessibilityLabel("Received amount")
                            .focused($focusedField, equals: .receivedAmount)
                    }
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
                focusedField = nil
                selectionScreen = .category
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
        recordRow("tag", showsDivider: false) {
            Button {
                focusedField = nil
                selectionScreen = .tags
            } label: {
                HStack {
                    Text("Labels").foregroundStyle(.primary)
                    Spacer()
                    if !draft.tagIDs.isEmpty { Text(selectedLabels).foregroundStyle(.secondary) }
                    chevron
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
    }

    /// Divides this record between people. Only offered once the record has an amount and a saved
    /// identity to attach the split to.
    @ViewBuilder private var splitRow: some View {
        if let splits = splitsViewModel, let value = try? AccountAmountInput.parse(amount), value > 0,
           draft.kind != .transfer, !currency.isEmpty {
            recordRow("person.2") {
                Button {
                    isSplitting = true
                } label: {
                    HStack {
                        Text("Split with people").foregroundStyle(.primary)
                        Spacer()
                        if let existing = splits.split(for: recordID) {
                            Text("\(existing.participants.count) people").foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .sheet(isPresented: $isSplitting) {
                SplitEditorView(viewModel: splits, recordID: recordID, amount: value,
                                currencyCode: currency)
            }
        }
    }

    /// Scanned receipt pages, with an OCR suggestion the user accepts rather than one applied
    /// silently over what they typed.
    @ViewBuilder private var receiptSection: some View {
        if let receiptUseCases {
            // Wrapped in a row so the scan button starts on the same column as every other field
            // rather than floating in the middle of the sheet.
            recordRow("doc.viewfinder") {
                ReceiptGalleryContent(
                    viewModel: ReceiptsViewModel(useCases: receiptUseCases, recordID: recordID),
                    showsScanIcon: false
                ) { reading in
                    if let value = reading.amount { amount = AccountAmountInput.text(value) }
                    if let date = reading.date { draft.date = date }
                }
            }
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
                WalletAmountField(amount: manualRate, placeholder: marketRatePlaceholder) {
                    TextField("", text: $manualRate.groupedAmount())
                        .accessibilityLabel("Exchange rate to \(currencyModel.homeCurrency)")
                        #if os(iOS)
                            .keyboardType(.decimalPad)
                        #endif
                }
                .monospacedDigit()
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
        return RecordAmountDisplay.grouped(CurrencyConverter.rounded(rate, currencyCode: "XXX"))
    }

    @ViewBuilder
    private var detailsSection: some View {
        sectionHeader("More Details")
        recordRow("square.and.pencil") {
            selectionButton("Note", value: draft.note.isEmpty ? nil : draft.note, screen: .note)
        }
        recordRow("person") {
            selectionButton("Payee", value: draft.payee.isEmpty ? nil : draft.payee, screen: .payee)
        }
        recordRow("creditcard") {
            selectionButton(
                "Payment type", value: draft.paymentType == .unspecified ? nil : draft.paymentType.title,
                screen: .payment)
        }
        exchangeRateRow
        splitRow
        receiptSection
        if !originalPhotoLoaded {
            if isLoadingOriginalPhoto { ProgressView("Loading existing photo…") }
            else { Button("Retry Loading Existing Photo") { Task { await loadOriginalPhoto() } } }
        }
        photoRow
        if isLoadingPhoto { ProgressView("Preparing photo…") }
    }

    /// One photo per record. An empty row asks where the photo should come from; a filled one opens
    /// the photo itself, which is where it can be deleted.
    @ViewBuilder private var photoRow: some View {
        recordRow("photo", showsDivider: false) {
            Button {
                focusedField = nil
                if draft.photoData == nil { choosingPhotoSource = true } else { viewingPhoto = true }
            } label: {
                HStack {
                    Text("Photo").foregroundStyle(.primary)
                    Spacer()
                    Text(draft.photoData == nil ? "None" : "1").foregroundStyle(.secondary)
                    chevron
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!originalPhotoLoaded || isLoadingPhoto)
        }
        .confirmationDialog("Add Photo", isPresented: $choosingPhotoSource, titleVisibility: .visible) {
            if RecordCameraAvailability.isAvailable {
                Button("Take Photo") { capturingPhoto = true }
            }
            Button("Choose from Library") { pickingPhotoFromLibrary = true }
            Button("Cancel", role: .cancel) {}
        }
        .photosPicker(isPresented: $pickingPhotoFromLibrary, selection: $photoItem, matching: .images)
        .sheet(isPresented: $viewingPhoto) {
            if let data = draft.photoData {
                RecordPhotoViewer(data: data) {
                    draft.photoData = nil
                    photoItem = nil
                }
            }
        }
        #if os(iOS)
            .fullScreenCover(isPresented: $capturingPhoto) {
                RecordCameraPicker(
                    onCapture: { data in Task { await applyCaptured(data) } },
                    onError: { errorMessage = $0 })
                    .ignoresSafeArea()
            }
        #endif
    }

    @ViewBuilder private var recurrenceSection: some View {
        sectionHeader("Repeat")
        RecurrenceFields(rule: $draft.recurrence, start: draft.date, style: .rows)
        if draft.recurrence != nil {
            Text("This record is saved now. Later occurrences are created when the app opens or becomes active. Manage them under Planning → Recurring.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, WalletMetrics.xLarge)
                .padding(.vertical, WalletMetrics.medium)
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
                if let value { Text(value).foregroundStyle(.secondary).lineLimit(1) }
                chevron
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func recordRow<Content: View>(
        _ symbol: String, color: Color = .gray, categoryTile: Bool = false, filledIcon: Bool = false,
        showsDivider: Bool = true, @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        RecordFormRow(
            symbol: symbol, color: color, category: viewModel.category(draft.categoryID), categoryTile: categoryTile,
            filledIcon: filledIcon, showsDivider: showsDivider, content: content)
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

    /// Shrinks a freshly taken photo on the same path a picked one takes, so both are stored alike.
    private func applyCaptured(_ data: Data) async {
        isLoadingPhoto = true
        defer { isLoadingPhoto = false }
        do {
            draft.photoData = try await Task.detached { try RecordPhoto.prepare(data) }.value
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
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
