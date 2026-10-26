//
//  PendingDraftStore.swift
//  AkhnaFin
//
//  Handoff draft antara App Intent ↔ app (A3). Dua slot terpisah agar bebas race:
//  - "confirming": draft yang sedang dikonfirmasi di Siri/Shortcuts —
//    DIBERSIHKAN saat konfirmasi selesai/batal.
//  - "edit-request": ditulis HANYA saat user menekan "Edit di App" di snippet;
//    dikonsumsi (baca + hapus) oleh app saat aktif.
//

import Foundation
import OSLog
import AkhnaFinCore
import ServiceInterfaces

private let draftLog = Logger(subsystem: "com.aban.AkhnaFin", category: "PendingDraft")

enum PendingDraftStore {
    /// Isi slot: draft + asal intent (source EKSPLISIT — jangan disimpulkan
    /// dari keberadaan gambar; review B6).
    private struct Payload: Codable {
        let draft: TransactionDraft
        let source: EntrySource
    }

    // MARK: Slot "confirming" (dipakai snippet untuk render ringkasan)

    static func stash(_ draft: TransactionDraft, source: EntrySource, receiptImage: Data? = nil) {
        write(Payload(draft: draft, source: source), to: stashURL)
        writeImage(receiptImage, to: stashImageURL)
    }

    static func currentStash() -> TransactionDraft? {
        read(from: stashURL)?.draft
    }

    /// Isi lengkap slot konfirmasi (draft + source + gambar) — dipakai tombol
    /// "Simpan" di snippet untuk commit langsung dari background.
    static func currentStashPayload() -> (draft: TransactionDraft, source: EntrySource, receiptImage: Data?)? {
        guard let payload = read(from: stashURL) else { return nil }
        return (payload.draft, payload.source, readData(from: stashImageURL))
    }

    static func clearStash() {
        removeItem(at: stashURL)
        removeItem(at: stashImageURL)
    }

    // MARK: Slot "edit-request" (handoff ke app)

    /// Dipanggil tombol "Edit di App": salin isi slot konfirmasi (draft+source+gambar)
    /// ke slot handoff — LogExpense/LogReceipt yang batal tetap membersihkan slot
    /// konfirmasi tanpa menyentuh handoff.
    static func promoteStashToEditRequest() {
        guard let payload = read(from: stashURL) else { return }
        write(payload, to: editRequestURL)
        writeImage(readData(from: stashImageURL), to: editRequestImageURL)
    }

    /// Baca sekaligus hapus — app memanggil ini saat menjadi aktif.
    static func consumeEditRequest() -> (draft: TransactionDraft, source: EntrySource, receiptImage: Data?)? {
        guard let payload = read(from: editRequestURL) else { return nil }
        let image = readData(from: editRequestImageURL)
        removeItem(at: editRequestURL)
        removeItem(at: editRequestImageURL)
        return (payload.draft, payload.source, image)
    }

    // MARK: - IO

    /// Kegagalan I/O tak pernah melempar (jalur snippet tak punya tempat
    /// tampilkan error) — tapi SELALU dicatat agar kegagalan tak sunyi.
    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("PendingDraft", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            draftLog.error("Gagal membuat direktori stash: \(error, privacy: .public)")
        }
        return dir
    }

    /// Tulis atau bersihkan file gambar slot (nil = hapus sisa lama agar tak nyasar).
    private static func writeImage(_ data: Data?, to url: URL) {
        if let data {
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                draftLog.error("Gagal menulis gambar \(url.lastPathComponent, privacy: .public): \(error, privacy: .public)")
            }
        } else {
            removeItem(at: url)
        }
    }

    private static func write(_ payload: Payload, to url: URL) {
        do {
            let data = try JSONEncoder().encode(payload)
            try data.write(to: url, options: .atomic)
        } catch {
            draftLog.error("Gagal menulis stash \(url.lastPathComponent, privacy: .public): \(error, privacy: .public)")
        }
    }

    private static func read(from url: URL) -> Payload? {
        guard let data = readData(from: url) else { return nil }
        do {
            return try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            draftLog.error("Stash korup \(url.lastPathComponent, privacy: .public): \(error, privacy: .public)")
            return nil
        }
    }

    /// File belum ada = state normal (belum pernah stash) — bukan error.
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

    private static var stashURL: URL { directory.appendingPathComponent("confirming.json") }
    private static var stashImageURL: URL { directory.appendingPathComponent("confirming-image.bin") }
    private static var editRequestURL: URL { directory.appendingPathComponent("edit-request.json") }
    private static var editRequestImageURL: URL { directory.appendingPathComponent("edit-request-image.bin") }
}