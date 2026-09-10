import SwiftUI
import WalletDomain

/// Holds the scanned pages for one record and the OCR suggestion drawn from them.
@MainActor
public final class ReceiptsViewModel: ObservableObject {
    @Published public private(set) var receipts: [Receipt] = []
    @Published public private(set) var isWorking = false
    @Published public var errorMessage: String?
    /// A suggestion from the newest scan, shown until the user accepts or dismisses it.
    @Published public var reading: ReceiptReading?

    private let useCases: ReceiptUseCases
    private let recordID: UUID

    public init(useCases: ReceiptUseCases, recordID: UUID) {
        self.useCases = useCases
        self.recordID = recordID
    }

    public var canAddMore: Bool { receipts.count < ReceiptUseCases.pageLimit }

    public func load() async {
        do { receipts = try await useCases.load(recordID: recordID) }
        catch { errorMessage = error.localizedDescription }
    }

    /// Stores freshly scanned pages, then reads the first one for an amount and date.
    public func add(pages: [Data]) async {
        guard !pages.isEmpty, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await useCases.append(pages: pages, to: recordID)
            await load()
            // The total is on the first page of a receipt far more often than not.
            if let first = pages.first {
                let found = await ReceiptTextReader.read(imageData: first)
                reading = found.isEmpty ? nil : found
            }
        } catch { errorMessage = error.localizedDescription }
    }

    public func delete(_ receipt: Receipt) async {
        do {
            try await useCases.delete(id: receipt.id)
            await load()
        } catch { errorMessage = error.localizedDescription }
    }
}

/// The scanned pages attached to a record, as a grouped-list section.
///
/// Use this inside a `List` or `Form`; the record editor is a `ScrollView` and uses
/// `ReceiptGalleryContent` directly instead.
public struct ReceiptGallerySection: View {
    @ObservedObject private var viewModel: ReceiptsViewModel
    private let onAccept: ((ReceiptReading) -> Void)?

    public init(viewModel: ReceiptsViewModel, onAccept: ((ReceiptReading) -> Void)? = nil) {
        self.viewModel = viewModel
        self.onAccept = onAccept
    }

    public var body: some View {
        Section {
            ReceiptGalleryContent(viewModel: viewModel, onAccept: onAccept)
        } header: {
            Text("Receipt")
        } footer: {
            Text(ReceiptGalleryContent.footer)
        }
    }
}

/// The scanned pages attached to a record, with the scanner and OCR suggestion.
public struct ReceiptGalleryContent: View {
    @ObservedObject private var viewModel: ReceiptsViewModel
    /// Called when the user accepts an OCR suggestion, so the editor can fill its fields.
    private let onAccept: ((ReceiptReading) -> Void)?
    @State private var isScanning = false
    @State private var zoomed: Receipt?

    public init(viewModel: ReceiptsViewModel, onAccept: ((ReceiptReading) -> Void)? = nil) {
        self.viewModel = viewModel
        self.onAccept = onAccept
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: WalletMetrics.small) {
            if !viewModel.receipts.isEmpty { pages }
            if let reading = viewModel.reading, let onAccept { suggestion(reading, accept: onAccept) }
            scanButton
            if viewModel.isWorking { ProgressView("Saving pages…") }
            if let message = viewModel.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .task { await viewModel.load() }
        #if canImport(VisionKit) && os(iOS)
            .fullScreenCover(isPresented: $isScanning) {
                ReceiptScanner(
                    onFinish: { pages in Task { await viewModel.add(pages: pages) } },
                    onError: { viewModel.errorMessage = $0 })
                    .ignoresSafeArea()
            }
        #endif
        .sheet(item: $zoomed) { receipt in
            NavigationStack {
                ScrollView([.horizontal, .vertical]) {
                    RecordPhotoView(data: receipt.imageData)
                }
                .navigationTitle("Page \(receipt.pageIndex + 1)")
                #if !os(macOS)
                    .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Done") { zoomed = nil } }
                    ToolbarItem {
                        Button("Delete", role: .destructive) {
                            let target = receipt
                            zoomed = nil
                            Task { await viewModel.delete(target) }
                        }
                    }
                }
            }
        }
    }

    static var footer: String {
        guard ReceiptScannerAvailability.isSupported else {
            return "Scanning needs a device with a camera. Existing pages still appear here."
        }
        return "Scan a receipt with the camera; multiple pages are kept in order. Pages are stored on this device and synced through iCloud, but are never included in exports."
    }

    private var pages: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: WalletMetrics.medium) {
                ForEach(viewModel.receipts) { receipt in
                    Button { zoomed = receipt } label: {
                        RecordPhotoView(data: receipt.imageData)
                            .frame(width: 90, height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: WalletMetrics.small, style: .continuous))
                            .overlay(alignment: .bottomTrailing) {
                                Text("\(receipt.pageIndex + 1)")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(4)
                                    .background(.black.opacity(0.6), in: Circle())
                                    .padding(4)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Receipt page \(receipt.pageIndex + 1)")
                }
            }
            .padding(.vertical, WalletMetrics.tight)
        }
    }

    /// OCR is a guess, so it is offered rather than applied.
    private func suggestion(_ reading: ReceiptReading, accept: @escaping (ReceiptReading) -> Void) -> some View {
        VStack(alignment: .leading, spacing: WalletMetrics.small) {
            Label("Found on this receipt", systemImage: "text.viewfinder")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
            if let amount = reading.amount {
                Text("Amount: \(AccountAmountInput.text(amount))").font(.callout)
            }
            if let date = reading.date {
                Text("Date: \(date.formatted(date: .abbreviated, time: .omitted))").font(.callout)
            }
            HStack {
                Button("Use These") {
                    accept(reading)
                    viewModel.reading = nil
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Button("Dismiss") { viewModel.reading = nil }
                    .controlSize(.small)
            }
        }
        .padding(.vertical, WalletMetrics.tight)
    }

    @ViewBuilder private var scanButton: some View {
        if ReceiptScannerAvailability.isSupported {
            Button { isScanning = true } label: {
                Label(viewModel.receipts.isEmpty ? "Scan Receipt" : "Add Pages",
                      systemImage: "doc.viewfinder")
            }
            .disabled(!viewModel.canAddMore || viewModel.isWorking)
            if !viewModel.canAddMore {
                Text("This record already holds the maximum of \(ReceiptUseCases.pageLimit) pages.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
