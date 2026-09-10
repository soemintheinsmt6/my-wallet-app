import Foundation
import Testing
import UniformTypeIdentifiers
import WalletDomain
@testable import WalletFeature

@MainActor
struct WalletCommandBusTests {
    @Test func newRecordCarriesTheKindAndBumpsTheRequest() {
        let bus = WalletCommandBus()
        #expect(bus.newRecordRequests == 0)

        bus.newRecord(kind: .income)
        #expect(bus.newRecordRequests == 1)
        #expect(bus.newRecordKind == .income)

        // Each invocation must be observable, even for the same kind, or a second ⌘N does nothing.
        bus.newRecord(kind: .income)
        #expect(bus.newRecordRequests == 2)
    }

    @Test func searchAndTabRequestsArePublished() {
        let bus = WalletCommandBus()
        bus.search()
        #expect(bus.searchRequests == 1)

        bus.show(.planning)
        #expect(bus.requestedTab == .planning)
    }

    /// ⌘1…⌘5 map onto the sidebar and tab order, so the count must stay in step.
    @Test func everyTabHasAShortcutSlot() {
        #expect(WalletTab.allCases.count == 5)
        #expect(WalletTab.allCases.first == .home)
        #expect(WalletTab.allCases.last == .more)
    }
}

struct RecordTransferTests {
    @Test func aDraggedRecordCarriesOnlyItsIdentifier() throws {
        let id = UUID()
        let transfer = RecordTransfer(recordID: id)
        let data = try JSONEncoder().encode(transfer)
        let decoded = try JSONDecoder().decode(RecordTransfer.self, from: data)

        #expect(decoded.recordID == id)
        // Nothing but the identifier travels: the drop side re-reads the live record.
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json.keys.sorted() == ["recordID"])
    }

    @Test func theDragTypeIsTheAppsOwnAndNotPlainText() {
        #expect(UTType.walletRecord.identifier == "com.app.My-Wallet.record")
    }
}
