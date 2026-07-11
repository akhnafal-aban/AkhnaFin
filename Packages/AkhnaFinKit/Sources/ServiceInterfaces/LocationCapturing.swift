import Foundation

/// Menangkap lokasi saat ini secara senyap ketika transaksi di-commit.
///
/// Mengembalikan `nil` bila izin ditolak, lokasi dimatikan di Settings, atau capture gagal —
/// penyimpanan transaksi tidak boleh ikut gagal karena lokasi.
public protocol LocationCapturing: Sendable {
    func captureCurrent() async -> CapturedPlace?
}
