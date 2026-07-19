import SwiftUI
import SwiftData
import Charts
import AkhnaFinCore
import Persistence

/// Dashboard fase C: ringkasan periode + donut kategori + bar tren.
///
/// Layout FIXED (reorderable container = enhancement iOS 27). Read reaktif via
/// `@Query`; agregasi murni di `TransactionAggregation` (Core) — View hanya
/// memetakan hasilnya ke Swift Charts.
struct DashboardView: View {
    @Query private var transactions: [MoneyTransaction]

    @State private var period: StatsPeriod = .month
    @State private var interval: DateInterval = StatsPeriod.month.interval(containing: .now)

    /// Maksimal irisan donut bernama; sisanya digulung ke "Lainnya" (HIG chart:
    /// 5–7 sektor agar terbaca).
    private static let maxSlices = 5

    var body: some View {
        NavigationStack {
            List {
                Section {
                    periodControls
                }

                if periodTransactions.isEmpty {
                    ContentUnavailableView(
                        "Belum ada transaksi di periode ini",
                        systemImage: "chart.pie",
                        description: Text("Ganti periode, atau catat lewat tombol + di tab Transaksi.")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    Section("Ringkasan") {
                        summaryRows
                    }
                    if !slices.isEmpty {
                        Section("Pengeluaran per Kategori") {
                            categoryDonut
                        }
                    }
                    Section(period == .year ? "Tren Bulanan" : "Tren Harian") {
                        trendBars
                    }
                }
            }
            .navigationTitle("Dashboard")
            .toolbarTitleDisplayMode(.inlineLarge)
            .onChange(of: period) {
                // Ganti granularitas → kembali ke periode yang memuat HARI INI
                // (offset minggu-ke-3 tak bermakna setelah pindah ke Bulan).
                interval = period.interval(containing: .now)
            }
        }
    }

    // MARK: - Kontrol periode

    private var periodControls: some View {
        VStack(spacing: 12) {
            Picker("Periode", selection: $period) {
                ForEach(StatsPeriod.allCases, id: \.self) { period in
                    Text(period.displayName).tag(period)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Button {
                    interval = period.step(interval, by: -1)
                } label: {
                    Image(systemName: "chevron.backward")
                }
                .accessibilityLabel("Periode sebelumnya")

                Spacer()
                Text(intervalLabel)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()

                Button {
                    interval = period.step(interval, by: 1)
                } label: {
                    Image(systemName: "chevron.forward")
                }
                .accessibilityLabel("Periode berikutnya")
                // Jangan melangkah ke masa depan — data belum ada.
                .disabled(interval.end > .now)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    /// Label periode: minggu "13–19 Jul 2026", bulan "Juli 2026", tahun "2026".
    private var intervalLabel: String {
        // `end` eksklusif → tampilkan hari terakhir inklusif.
        let lastDay = interval.end.addingTimeInterval(-1)
        switch period {
        case .week:
            let start = interval.start.formatted(.dateTime.day().month(.abbreviated))
            let end = lastDay.formatted(.dateTime.day().month(.abbreviated).year())
            return "\(start) – \(end)"
        case .month:
            return interval.start.formatted(.dateTime.month(.wide).year())
        case .year:
            return interval.start.formatted(.dateTime.year())
        }
    }

    // MARK: - Data turunan (agregasi di Core)

    private var periodTransactions: [MoneyTransaction] {
        transactions.filter { interval.contains($0.date) }
    }

    private var totals: (expense: Decimal, income: Decimal) {
        TransactionAggregation.totals(periodTransactions)
    }

    /// Top-N kategori + gulung sisanya ke "Lainnya" (donut tetap terbaca).
    private var slices: [TransactionAggregation.CategorySlice] {
        let all = TransactionAggregation.expenseByCategory(periodTransactions)
        guard all.count > Self.maxSlices + 1 else { return all }
        let top = all.prefix(Self.maxSlices)
        let restTotal = all.dropFirst(Self.maxSlices).reduce(Decimal(0)) { $0 + $1.total }
        return top + [.init(name: "Lainnya", colorHex: "", total: restTotal)]
    }

    private var trendSeries: [(day: Date, total: Decimal)] {
        period == .year
            ? TransactionAggregation.monthlyExpenseSeries(periodTransactions, in: interval)
                .map { (day: $0.month, total: $0.total) }
            : TransactionAggregation.dailyExpenseSeries(periodTransactions, in: interval)
    }

    // MARK: - Ringkasan

    private var summaryRows: some View {
        Group {
            summaryRow("Pengeluaran", totals.expense, color: .red, icon: "arrow.up.circle.fill")
            summaryRow("Pemasukan", totals.income, color: .green, icon: "arrow.down.circle.fill")
            summaryRow(
                "Selisih", totals.income - totals.expense,
                color: totals.income >= totals.expense ? .green : .red,
                icon: "equal.circle.fill"
            )
        }
    }

    private func summaryRow(_ title: String, _ amount: Decimal, color: Color, icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .foregroundStyle(color)
            Spacer()
            Text(CurrencyFormatter.string(from: amount))
                .font(.body.monospacedDigit().weight(.semibold))
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Donut kategori

    private var categoryDonut: some View {
        Chart(slices, id: \.name) { slice in
            SectorMark(
                angle: .value("Total", doubleValue(slice.total)),
                innerRadius: .ratio(0.618),
                angularInset: 1.5
            )
            .cornerRadius(4)
            .foregroundStyle(by: .value("Kategori", slice.name))
            .accessibilityLabel(slice.name)
            .accessibilityValue(CurrencyFormatter.string(from: slice.total))
        }
        .chartForegroundStyleScale(domain: slices.map(\.name), range: slices.map(sliceColor))
        .chartLegend(position: .bottom, spacing: 12)
        .frame(minHeight: 220)
        .padding(.vertical, 8)
    }

    /// Warna irisan dari colorHex kategori; bucket tanpa warna → abu-abu
    /// (bukan accent — accent menyesatkan seolah kategori istimewa).
    private func sliceColor(_ slice: TransactionAggregation.CategorySlice) -> Color {
        slice.colorHex.isEmpty ? Color.gray.opacity(0.55) : Color(hex: slice.colorHex)
    }

    // MARK: - Tren

    private var trendBars: some View {
        Chart(trendSeries, id: \.day) { point in
            BarMark(
                x: .value("Tanggal", point.day, unit: period == .year ? .month : .day),
                y: .value("Pengeluaran", doubleValue(point.total))
            )
            .foregroundStyle(.tint)
            .accessibilityLabel(point.day.formatted(
                period == .year ? .dateTime.month(.wide) : .dateTime.day().month()
            ))
            .accessibilityValue(CurrencyFormatter.string(from: point.total))
        }
        .chartXAxis {
            AxisMarks(values: .automatic) { _ in
                AxisGridLine()
                AxisValueLabel(format: period == .year
                    ? .dateTime.month(.narrow)
                    : .dateTime.day())
            }
        }
        .frame(minHeight: 180)
        .padding(.vertical, 8)
    }

    /// Decimal → Double untuk sumbu chart (Decimal bukan tipe plottable).
    private func doubleValue(_ decimal: Decimal) -> Double {
        NSDecimalNumber(decimal: decimal).doubleValue
    }
}

#Preview {
    let container = try! ModelContainerFactory.make(mode: .inMemory)
    try! CategorySeeder.seedIfNeeded(context: container.mainContext)
    let context = container.mainContext
    let categories = try! context.fetch(FetchDescriptor<TransactionCategory>())
    let calendar = Calendar.current
    for offset in 0..<20 {
        let category = categories[offset % categories.count]
        let transaction = MoneyTransaction(
            amount: Decimal((offset + 1) * 7500),
            type: offset % 6 == 5 ? .income : .expense,
            date: calendar.date(byAdding: .day, value: -offset, to: .now)!,
            note: "Dummy \(offset)",
            category: category
        )
        context.insert(transaction)
    }
    return DashboardView()
        .modelContainer(container)
}
