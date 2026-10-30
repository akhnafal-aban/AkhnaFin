import SwiftUI
import SwiftData
import Charts
import AkhnaFinCore
import Persistence

struct DashboardView: View {
    @Query private var transactions: [MoneyTransaction]
    @Query private var debts: [DebtRecord]

    @State private var period: StatsPeriod = .month
    @State private var interval: DateInterval = StatsPeriod.month.interval(containing: .now)
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 36
    @ScaledMetric(relativeTo: .title3) private var miniStatSize: CGFloat = 20

    private let debtRepository: DebtRepository?

    init(debtRepository: DebtRepository? = nil) {
        self.debtRepository = debtRepository
    }

    private static let maxSlices = 5

    var body: some View {
        NavigationStack {
            List {
                Section {
                    periodControls
                }
                .warmRow()

                if periodTransactions.isEmpty {
                    ContentUnavailableView(
                        "Periode ini masih kosong",
                        systemImage: "chart.pie",
                        description: Text("Catat lewat tombol + di tab Transaksi — atau bilang saja ke Siri, sekarang paham Bahasa Indonesia.")
                    )
                    .listRowBackground(Color.clear)

                    if let debtRepository {
                        Section("Hutang") {
                            debtCard(repository: debtRepository)
                        }
                        .warmRow()
                    }
                } else {
                    Section("Ringkasan") {
                        summaryRows
                    }
                    .warmRow()
                    if !slices.isEmpty {
                        Section("Pengeluaran per Kategori") {
                            categoryDonut
                        }
                        .warmRow()
                    }
                    if let debtRepository {
                        Section("Hutang") {
                            debtCard(repository: debtRepository)
                        }
                        .warmRow()
                    }

                    Section(period == .year ? "Tren Bulanan" : "Tren Harian") {
                        trendBars
                    }
                    .warmRow()
                }
            }
            .warmDarkBackground()
            .contentMargins(.top, 8, for: .scrollContent)
            .navigationTitle("Dashboard")
            .toolbarTitleDisplayMode(.inlineLarge)
            .onChange(of: period) {
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
                }                .accessibilityLabel("Periode sebelumnya")

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
                .disabled(interval.end > .now)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 8)
    }

    private var intervalLabel: String {
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

    /// Hero: selisih periode (angka besar ringan) + dua statistik pendamping.
    private var summaryRows: some View {
        let net = totals.income - totals.expense
        let isSurplus = net >= 0
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(isSurplus ? "Sisa periode ini" : "Melebihi pemasukan")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(signed(net))
                    .font(Font.system(size: heroSize, weight: .light).monospacedDigit())
                    .foregroundStyle(isSurplus ? AppTheme.lime : AppTheme.expenseRed)
            }

            HStack(spacing: 24) {
                miniStat("Pengeluaran", totals.expense, color: AppTheme.expenseRed)
                miniStat("Pemasukan", totals.income, color: AppTheme.lime)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func miniStat(_ title: String, _ amount: Decimal, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(CurrencyFormatter.string(from: amount))
                .font(Font.system(size: miniStatSize, weight: .light).monospacedDigit())
                .foregroundStyle(AppTheme.ink)
        }
    }

    private func signed(_ amount: Decimal) -> String {
        let formatted = CurrencyFormatter.string(from: abs(amount))
        return amount < 0 ? "-\(formatted)" : "+\(formatted)"
    }

    // MARK: - Kartu Hutang

    private func debtCard(repository: DebtRepository) -> some View {
        let summary = DebtSummary.outstanding(debts)
        return NavigationLink {
            DebtListView(repository: repository)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Aku Berutang", systemImage: "arrow.up.right.circle.fill")
                        .foregroundStyle(AppTheme.expenseRed)
                    Spacer()
                    Text(CurrencyFormatter.string(from: summary.iOwe))
                        .font(.body.monospacedDigit().weight(.semibold))
                }
                HStack {
                    Label("Piutang", systemImage: "arrow.down.left.circle.fill")
                        .foregroundStyle(AppTheme.lime)
                    Spacer()
                    Text(CurrencyFormatter.string(from: summary.owedToMe))
                        .font(.body.monospacedDigit().weight(.semibold))
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Donut kategori

    private var categoryDonut: some View {
        VStack(spacing: 12) {
            Chart(slices, id: \.name) { slice in
                SectorMark(
                    angle: .value("Total", doubleValue(slice.total)),
                    innerRadius: .ratio(0.618),
                    angularInset: 1.5
                )
                .cornerRadius(4)
                .foregroundStyle(sliceColor(slice))
                .accessibilityLabel(slice.name)
                .accessibilityValue(CurrencyFormatter.string(from: slice.total))
            }
            .frame(minHeight: 200)
            .overlay {
                VStack(spacing: 2) {
                    Text("Total")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(CurrencyFormatter.string(from: totals.expense))
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                }
                .allowsHitTesting(false)
            }

            FlowLegend(items: slices.map { ($0.name, sliceColor($0)) })
        }
        .padding(.vertical, 8)
    }

    private func sliceColor(_ slice: TransactionAggregation.CategorySlice) -> Color {
        slice.colorHex.isEmpty ? Color(.systemGray3) : Color(hex: slice.colorHex)
    }

    // MARK: - Tren

    private var trendBars: some View {
        Chart(trendSeries, id: \.day) { point in
            BarMark(
                x: .value("Tanggal", point.day, unit: period == .year ? .month : .day),
                y: .value("Pengeluaran", doubleValue(point.total))
            )
            .foregroundStyle(AppTheme.expenseRed)
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

    private func doubleValue(_ decimal: Decimal) -> Double {
        NSDecimalNumber(decimal: decimal).doubleValue
    }
}

private struct FlowLegend: View {
    let items: [(name: String, color: Color)]

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(items, id: \.name) { item in
                HStack(spacing: 8) {
                    Circle().fill(item.color).frame(width: 8, height: 8)
                    Text(item.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
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
