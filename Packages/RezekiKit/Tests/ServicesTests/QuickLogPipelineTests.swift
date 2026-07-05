import Testing
import Foundation
import ServiceInterfaces
@testable import Services

@Suite("QuickLogPipeline — timeout & mapping error")
struct QuickLogPipelineTests {
    @Test("Parse sukses diteruskan apa adanya")
    func successPassthrough() async throws {
        let pipeline = QuickLogPipeline(parser: MockTransactionParser())
        let draft = try await pipeline.parseDraft(from: "buy meatballs 20k")
        #expect(draft.rawInput == "buy meatballs 20k")
        #expect(draft.amount == 20000)
    }

    @Test("Parser lambat melebihi batas → timedOut, bukan stuck")
    func slowParserTimesOut() async {
        let pipeline = QuickLogPipeline(
            parser: MockTransactionParser(delay: .milliseconds(500)),
            timeout: .milliseconds(30)
        )
        await #expect(throws: QuickLogError.timedOut) {
            _ = try await pipeline.parseDraft(from: "x")
        }
    }

    @Test("Parser cepat menang atas batas waktu")
    func fastParserBeatsTimeout() async throws {
        let pipeline = QuickLogPipeline(
            parser: MockTransactionParser(delay: .milliseconds(5)),
            timeout: .seconds(2)
        )
        let draft = try await pipeline.parseDraft(from: "coffee 8k")
        #expect(draft.rawInput == "coffee 8k")
    }

    @Test("Error parser ter-map granular")
    func errorMapping() async {
        let unavailable = QuickLogPipeline(
            parser: MockTransactionParser(error: .modelUnavailable("Aktifkan Apple Intelligence."))
        )
        await #expect(throws: QuickLogError.modelUnavailable("Aktifkan Apple Intelligence.")) {
            _ = try await unavailable.parseDraft(from: "x")
        }

        let failed = QuickLogPipeline(
            parser: MockTransactionParser(error: .parsingFailed("Gagal memahami."))
        )
        await #expect(throws: QuickLogError.parseFailed("Gagal memahami.")) {
            _ = try await failed.parseDraft(from: "x")
        }
    }
}
