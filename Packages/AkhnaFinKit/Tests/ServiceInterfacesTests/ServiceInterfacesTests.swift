import Testing
import Foundation
@testable import ServiceInterfaces

@Suite("ServiceInterfaces — draft & mock")
struct ServiceInterfacesTests {
    @Test("Mock parser mengisi rawInput dengan teks asli")
    func mockParserEchoesRawInput() async throws {
        let parser = MockTransactionParser()
        let draft = try await parser.parse("beli bakso 20k di kantin kantor")
        #expect(draft.rawInput == "beli bakso 20k di kantin kantor")
        #expect(draft.amount == 20000)
        #expect(draft.categoryName == "Main Food")
    }

    @Test("Mock parser batch memecah per baris")
    func mockParserBatchSplitsLines() async throws {
        let parser = MockTransactionParser()
        let drafts = try await parser.parseBatch("nasi 15k\nkopi 8k\nparkir 2k")
        #expect(drafts.count == 3)
        #expect(drafts[1].rawInput == "kopi 8k")
    }

    @Test("TransactionDraft roundtrip Codable (handoff intent → app)")
    func draftCodableRoundtrip() throws {
        let draft = TransactionDraft(
            amount: 20000,
            type: .expense,
            date: Date(timeIntervalSince1970: 1_750_000_000),
            note: "bakso",
            merchant: "Kantin Kantor",
            categoryName: "Main Food",
            subcategoryName: "",
            rawInput: "buy meatballs 20k",
            isReimbursable: true,
            reimbursedBy: "Budi"
        )
        let data = try JSONEncoder().encode(draft)
        let decoded = try JSONDecoder().decode(TransactionDraft.self, from: data)
        #expect(decoded == draft)
        #expect(decoded.isReimbursable == true)
        #expect(decoded.reimbursedBy == "Budi")
    }

    @Test("TransactionDraft default reimbursable false")
    func draftReimbursableDefaults() throws {
        let draft = TransactionDraft(amount: 10000, rawInput: "test")
        #expect(draft.isReimbursable == false)
        #expect(draft.reimbursedBy.isEmpty)
    }

    @Test("Mock location mengembalikan tempat yang di-set")
    func mockLocationReturnsPlace() async {
        let capturer = MockLocationCapturer()
        let place = await capturer.captureCurrent()
        #expect(place?.placeName == "Jakarta")

        let disabled = MockLocationCapturer(place: nil)
        #expect(await disabled.captureCurrent() == nil)
    }
}
