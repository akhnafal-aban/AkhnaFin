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
import AkhnaFinCore
import ServiceInterfaces

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
        return (payload.draft, payload.source, try? Data(contentsOf: stashImageURL))
    }

    static func clearStash() {
        try? FileManager.default.removeItem(at: stashURL)
        try? FileManager.default.removeItem(at: stashImageURL)
    }

    // MARK: Slot "edit-request" (handoff ke app)

    /// Dipanggil tombol "Edit di App": salin isi slot konfirmasi (draft+source+gambar)
    /// ke slot handoff — LogExpense/LogReceipt yang batal tetap membersihkan slot
    /// konfirmasi tanpa menyentuh handoff.
    static func promoteStashToEditRequest() {
        guard let payload = read(from: stashURL) else { return }
        write(payload, to: editRequestURL)
        writeImage(try? Data(contentsOf: stashImageURL), to: editRequestImageURL)
    }

    /// Baca sekaligus hapus — app memanggil ini saat menjadi aktif.
    static func consumeEditRequest() -> (draft: TransactionDraft, source: EntrySource, receiptImage: Data?)? {
        guard let payload = read(from: editRequestURL) else { return nil }
        let image = try? Data(contentsOf: editRequestImageURL)
        try? FileManager.default.removeItem(at: editRequestURL)
        try? FileManager.default.removeItem(at: editRequestImageURL)
        return (payload.draft, payload.source, image)
    }

    // MARK: - IO

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("PendingDraft", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var stashURL: URL { directory.appendingPathComponent("confirming.json") }
    private static var stashImageURL: URL { directory.appendingPathComponent("confirming-image.bin") }
    private static var editRequestURL: URL { directory.appendingPathComponent("edit-request.json") }
    private static var editRequestImageURL: URL { directory.appendingPathComponent("edit-request-image.bin") }

    /// Tulis atau bersihkan file gambar slot (nil = hapus sisa lama agar tak nyasar).
    private static func writeImage(_ data: Data?, to url: URL) {
        if let data {
            try? data.write(to: url, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func write(_ payload: Payload, to url: URL) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func read(from url: URL) -> Payload? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }
}
