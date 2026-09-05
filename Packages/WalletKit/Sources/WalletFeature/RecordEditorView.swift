import PhotosUI
import SwiftUI
import WalletDomain

struct RecordEditorView: View {
    @ObservedObject var viewModel: RecordsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft = RecordDraft()
    @State private var recordID = UUID()
    @State private var amount = ""
    @State private var receivedAmount = ""
    @State private var selectingCategory = false
    @State private var selectingTags = false
    @State private var selectingDate = false
    @State private var photoItem: PhotosPickerItem?
    @State private var isLoadingPhoto = false
    @State private var errorMessage: String?
    @AppStorage("records.lastUsedAccountID") private var lastUsedAccountID = ""
    @AppStorage("records.lastUsedPaymentType") private var lastUsedPaymentType = PaymentType.unspecified.rawValue
    @FocusState private var focusedField: InputField?
    private enum InputField: Hashable { case amount, receivedAmount, note, payee }
    @State private var didFocusAmount = false
    @State private var selectionScreen: SelectionScreen?
    private enum SelectionScreen: String, Hashable { case account, destination, payment }
    @ScaledMetric(relativeTo: .largeTitle) private var amountFontSize = 60

    private var amountColor: Color { draft.kind == .expense ? .red : draft.kind == .income ? .green : .primary }
    private var canSave: Bool {
        guard !viewModel.isSaving, !isLoadingPhoto,
              let value = try? AccountAmountInput.parse(amount) else { return false }
        var values = draft
        values.amount = value
        if crossCurrency {
            guard let received = try? AccountAmountInput.parse(receivedAmount) else { return false }
            values.receivedAmount = received
        }
        return (try? values.validate()) != nil
    }

    private var currency: String { viewModel.account(draft.accountID)?.currencyCode ?? "" }
    private var destinationCurrency: String { viewModel.account(draft.destinationAccountID)?.currencyCode ?? "" }
    private var crossCurrency: Bool { draft.kind == .transfer && !currency.isEmpty && !destinationCurrency.isEmpty && currency != destinationCurrency }
    private var selectedLabels: String {
        let names = viewModel.tags.filter { draft.tagIDs.contains($0.id) }.map(\.name)
        return names.isEmpty ? "None" : names.joined(separator: ", ")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                VStack(spacing: 12) {
                    Picker("Record type", selection: $draft.kind) {
                        ForEach(RecordKind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    HStack(spacing: 16) {
                        if !currency.isEmpty {
                        Text(currency)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.quaternary.opacity(0.4), in: Capsule())
                            .accessibilityLabel("Currency \(currency)")
                        }
                        ZStack(alignment: .trailing) {
                            // The overlay keeps the sign next to the digits without storing it in the input.
                            Text("\(draft.kind == .expense ? "−" : draft.kind == .income ? "+" : "")\(RecordAmountDisplay.grouped(amount))")
                                .lineLimit(1)
                                .minimumScaleFactor(0.35)
                                .accessibilityHidden(true)
                            TextField("", text: $amount)
                                .focused($focusedField, equals: .amount)
                                .textFieldStyle(.plain)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(.clear)
                                .tint(.clear)
                                .accessibilityLabel("\(draft.kind.title) amount")
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif
                        }
                        .font(.system(size: amountFontSize, weight: .regular))
                        .monospacedDigit()
                        .foregroundStyle(amountColor)
                        .frame(maxWidth: .infinity, minHeight: 76)
                    }
                    .padding(.vertical, 4)
                    if crossCurrency {
                        HStack {
                            Text("Received \(destinationCurrency)")
                            TextField("0", text: $receivedAmount).multilineTextAlignment(.trailing).accessibilityLabel("Received amount")
                                .focused($focusedField, equals: .receivedAmount)
                        }
                        Text("Enter the actual amount received. No exchange rate is assumed.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                sectionHeader("General")
                recordRow("wallet.bifold.fill", color: .blue, filledIcon: true) {
                    selectionButton(draft.kind == .transfer ? "From account" : "Account", value: viewModel.account(draft.accountID)?.name, screen: .account)
                }
                    if draft.kind == .transfer {
                        recordRow("wallet.bifold.fill", color: .blue, filledIcon: true) {
                        selectionButton("To account", value: viewModel.account(draft.destinationAccountID)?.name, screen: .destination)
                        }
                    }
                    recordRow(viewModel.category(draft.categoryID)?.symbol ?? "questionmark", color: viewModel.category(draft.categoryID)?.colorToken.color ?? .gray, categoryTile: true) {
                    Button { selectingCategory = true } label: {
                        HStack {
                            Text("Category").foregroundStyle(.primary)
                            Spacer()
                            Text(draft.categoryID == nil ? (draft.kind == .transfer ? "Optional" : "Required") : viewModel.categoryTitle(draft.categoryID))
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
                                        Button { draft.categoryID = category.id } label: {
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
                        Button {
                            focusedField = nil
                            selectingDate = true
                        } label: {
                            HStack {
                                Text("Date & Time")
                                Spacer()
                                Text(dateTimeText)
                                    .multilineTextAlignment(.trailing)
                            }
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens the date and time picker")
                        .popover(isPresented: $selectingDate) {
                            VStack(spacing: 0) {
                                ScrollView {
                                    DatePicker("Date & Time", selection: $draft.date, displayedComponents: [.date, .hourAndMinute])
                                        .datePickerStyle(.graphical)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .padding(.horizontal, 16)
                                        .padding(.top, 16)
                                }
                            }
                            .padding(.bottom, 16)
                            .frame(width: 320, height: 400)
                            .presentationCompactAdaptation(.popover)
                        }
                    }
                    recordRow("tag") {
                        Button { selectingTags = true } label: {
                            HStack {
                                Text("Labels").foregroundStyle(.primary)
                                Spacer()
                                if !draft.tagIDs.isEmpty { Text(selectedLabels).foregroundStyle(.secondary) }
                                Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(.blue)
                            }
                        }.buttonStyle(.plain)
                    }
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
                        selectionButton("Payment type", value: draft.paymentType == .unspecified ? nil : draft.paymentType.title, screen: .payment)
                    }
                    let photoTitle = draft.photoData == nil ? "Attach Photo" : "Replace Photo"
                    recordRow("photo") {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Text(photoTitle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    }
                    if isLoadingPhoto { ProgressView("Preparing photo…") }
                    if let data = draft.photoData {
                        RecordPhotoView(data: data)
                        Button("Remove Photo", role: .destructive) { draft.photoData = nil; photoItem = nil }
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
            .disabled(viewModel.isSaving)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    Divider()
                    Button { Task { await save() } } label: {
                        HStack {
                            Spacer()
                            if viewModel.isSaving { ProgressView() } else { Text("Save").font(.headline) }
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
            .navigationTitle("Add Record")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(viewModel.isSaving)
                }
            }
            .sheet(isPresented: $selectingCategory) { RecordCategoryPicker(viewModel: viewModel, kind: draft.kind, selection: $draft.categoryID) }
            .sheet(isPresented: $selectingTags) { RecordTagPicker(viewModel: viewModel, selection: $draft.tagIDs) }
            .navigationDestination(item: $selectionScreen) { screen in
                switch screen {
                case .account:
                    RecordAccountSelection(accounts: viewModel.accounts, selection: $draft.accountID, title: draft.kind == .transfer ? "From account" : "Account")
                case .destination:
                    RecordAccountSelection(accounts: viewModel.accounts.filter { $0.id != draft.accountID }, selection: $draft.destinationAccountID, title: "To account")
                case .payment:
                    RecordPaymentSelection(selection: $draft.paymentType)
                }
            }
            .task {
                guard !didFocusAmount else { return }
                didFocusAmount = true
                if let id = UUID(uuidString: lastUsedAccountID), viewModel.account(id) != nil {
                    draft.accountID = id
                }
                draft.paymentType = PaymentType(rawValue: lastUsedPaymentType) ?? .unspecified
                await Task.yield()
                focusedField = .amount
            }
            .interactiveDismissDisabled(viewModel.isSaving)
            .task(id: photoItem) { await loadPhoto() }
            .onChange(of: draft.accountID) { _, id in
                if draft.destinationAccountID == id { draft.destinationAccountID = nil }
            }
        }
        #if os(macOS)
        .frame(minWidth: 540, minHeight: 720)
        #endif
    }

    private var chevron: some View {
        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
    }

    private var dateTimeText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter.string(from: draft.date)
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

    private func recordRow<Content: View>(_ symbol: String, color: Color = .gray, categoryTile: Bool = false, filledIcon: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if categoryTile, let category = viewModel.category(draft.categoryID) {
                    CategoryIcon(category: category)
                } else if categoryTile || filledIcon {
                    Image(systemName: symbol)
                        .font(.system(size: 18))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(color, in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: symbol)
                    .font(.system(size: 18))
                    .foregroundStyle(color)
                    .frame(width: 36, height: 36)
                    .accessibilityHidden(true)
                }
                HStack { content() }
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            Divider().padding(.leading, 66)
        }
    }

    private func loadPhoto() async {
        guard let item = photoItem else { isLoadingPhoto = false; return }
        isLoadingPhoto = true
        defer { if item == photoItem { isLoadingPhoto = false } }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { throw RecordValidationError.invalidPhoto }
            let prepared = try await Task.detached { try RecordPhoto.prepare(data) }.value
            try Task.checkCancellation()
            if item == photoItem { draft.photoData = prepared }
        } catch is CancellationError {
        } catch { if item == photoItem { errorMessage = error.localizedDescription } }
    }

    private func save() async {
        errorMessage = nil
        do {
            var values = draft
            values.amount = try AccountAmountInput.parse(amount)
            values.receivedAmount = crossCurrency ? try AccountAmountInput.parse(receivedAmount) : nil
            try await viewModel.save(id: recordID, draft: values)
            lastUsedAccountID = values.accountID?.uuidString ?? ""
            lastUsedPaymentType = values.paymentType.rawValue
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}
