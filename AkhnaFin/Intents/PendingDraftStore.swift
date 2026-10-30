//
//  PendingDraftStore.swift
//  AkhnaFin
//

import Foundation
import OSLog
import AkhnaFinCore
import ServiceInterfaces

private let draftLog = Logger(subsystem: "com.aban.AkhnaFin", category: "PendingDraft")

/// Handoff intent → app: transaksi SUDAH tersimpan oleh intent; app tinggal
/// membuka form EDIT atas transaksi itu. Satu commit, tidak mungkin dobel.
enum PendingDraftStore {
    private struct Payload: Codable {
        let transactionID: UUID
        let source: EntrySource
    }

    static func requestEdit(transactionID: UUID, source: EntrySource) {
        write(Payload(transactionID: transactionID, source: source), to: editRequestURL)
    }

    static func consumeEditRequest() -> (transactionID: UUID, source: EntrySource)? {
        guard let payload = read(from: editRequestURL) else { return nil }
        removeItem(at: editRequestURL)
        return (payload.transactionID, payload.source)
    }

    // MARK: - IO

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("PendingDraft", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            draftLog.error("Gagal membuat direktori handoff: \(error, privacy: .public)")
        }
        return dir
    }

    private static func write(_ payload: Payload, to url: URL) {
        do {
            let data = try JSONEncoder().encode(payload)
            try data.write(to: url, options: .atomic)
        } catch {
            draftLog.error("Gagal menulis handoff \(url.lastPathComponent, privacy: .public): \(error, privacy: .public)")
        }
    }

    private static func read(from url: URL) -> Payload? {
        guard let data = readData(from: url) else { return nil }
        do {
            return try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            draftLog.error("Handoff korup \(url.lastPathComponent, privacy: .public): \(error, privacy: .public)")
            return nil
        }
    }

    private static func readData(from url: URL) -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch {
            if !isMissingFile(error) {
                draftLog.error("Gagal membaca \(url.lastPathComponent, privacy: .public): \(error, privacy: .public)")
            }
            return nil
        }
    }

    private static func removeItem(at url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            if !isMissingFile(error) {
                draftLog.error("Gagal menghapus \(url.lastPathComponent, privacy: .public): \(error, privacy: .public)")
            }
        }
    }

    private static func isMissingFile(_ error: any Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileNoSuchFileError
    }

    private static var editRequestURL: URL { directory.appendingPathComponent("edit-request.json") }
}