import SwiftUI
import SwiftData
import AkhnaFinCore
import Persistence

/// Daftar hutang/piutang: belum lunas dulu (terlambat disorot), lalu lunas.
/// Read reaktif `@Query`; mutasi lewat `DebtRepository` (pola proyek).
struct DebtListView: View {
    @Query(sort: \DebtRecord.createdAt, order: .reverse) private var records: [DebtRecord]
    @State private var isAdding = false
    @State private var deleteFailed = false

    let repository: DebtRepository

    private var openRecords: [DebtRecord] {
        records.filter { !$0.isSettled }
            .sorted { lhs, rhs in
                switch (lhs.isOverdue(), rhs.isOverdue()) {
                case (true, false): true
                case (false, true): false
                default: (lhs.dueDate ?? .distantFuture) < (rhs.dueDate ?? .distantFuture)
                }
            }
    }

    private var settledRecords: [DebtRecord] {
        records.filter(\.isSettled)
    }

    var body: some View {
        List {
            if !openRecords.isEmpty {
                Section("Belum Lunas") {
                    ForEach(openRecords, id: \.id) { record in
                        row(record)
                    }
                }
            }
            if !settledRecords.isEmpty {
                Section("Lunas") {
                    ForEach(settledRecords, id: \.id) { record in
                        row(record)
                    }
                }
            }
        }
        .navigationTitle("Hutang")
        .toolbar {
            Button {
                isAdding = true
            } label: {
                Label("Tambah", systemImage: "plus")
            }
        }
        .sheet(isPresented: $isAdding) {
            DebtFormView(mode: .add, repository: repository)
        }
        .alert("Gagal menghapus", isPresented: $deleteFailed) {
            Button("OK", role: .cancel) {}
        }
        .overlay {
            if records.isEmpty {
                ContentUnavailableView(
                    "Belum ada hutang",
                    systemImage: "person.2.badge.minus",
                    description: Text("Tap + untuk mencatat hutang atau piutang pertamamu.")
                )
            }
        }
    }

    private func row(_ record: DebtRecord) -> some View {
        NavigationLink {
            DebtDetailView(record: record, repository: repository)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: record.direction == .iOwe
                    ? "arrow.up.right.circle.fill"
                    : "arrow.down.left.circle.fill")
                    .foregroundStyle(record.direction == .iOwe ? .red : .green)
                    .font(.title3)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(record.counterparty)
                    HStack(spacing: 4) {
                        if record.isOverdue() {
                            // Ikon + teks, bukan warna saja (HIG aksesibilitas).
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text("Terlambat")
                        } else if let dueDate = record.dueDate, !record.isSettled {
                            Text("Jatuh tempo \(dueDate.formatted(.dateTime.day().month()))")
                        } else {
                            Text(record.direction.displayName)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(record.isOverdue() ? .red : .secondary)
                }

                Spacer()
                Text(CurrencyFormatter.string(from: record.isSettled ? record.principal : record.remaining))
                    .font(.body.monospacedDigit().weight(.semibold))
                    .foregroundStyle(record.isSettled ? .secondary : .primary)
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                do {
                    try repository.delete(record)
                } catch {
                    deleteFailed = true
                }
            } label: {
                Label("Hapus", systemImage: "trash")
            }
        }
    }
}

#Preview {
    let container = try! ModelContainerFactory.make(mode: .inMemory)
    let context = container.mainContext
    let repository = DebtRepository(context: context)
    try! repository.create(
        counterparty: "SPayLater", direction: .iOwe, principal: 750_000,
        dueDate: .now.addingTimeInterval(-86_400)
    )
    try! repository.create(counterparty: "Budi", direction: .owedToMe, principal: 150_000)
    return NavigationStack {
        DebtListView(repository: repository)
    }
    .modelContainer(container)
}
