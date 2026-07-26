import SwiftUI
import MapKit
import AkhnaFinCore
import Persistence

/// Detail transaksi READ-ONLY (HIG: tap baris = lihat, edit = aksi terpisah).
/// Menampilkan lokasi (peta), gambar resi, dan metadata yang tak muncul di form
/// edit. Edit lewat tombol toolbar → `TransactionFormView(.edit)`.
struct TransactionDetailView: View {
    let transaction: MoneyTransaction
    let repository: TransactionRepository

    @State private var isEditing = false
    @State private var isReceiptEnlarged = false

    var body: some View {
        List {
            heroSection
            if let coordinate { locationSection(coordinate) }
            if let receiptImage { receiptSection(receiptImage) }
            metadataSection
        }
        .navigationTitle("Detail")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { isEditing = true }
            }
        }
        .sheet(isPresented: $isEditing) {
            TransactionFormView(mode: .edit(transaction), repository: repository)
        }
        .fullScreenCover(isPresented: $isReceiptEnlarged) {
            if let receiptImage {
                ReceiptViewer(image: receiptImage) { isReceiptEnlarged = false }
            }
        }
    }

    // MARK: - Hero (nominal + kategori)

    private var heroSection: some View {
        Section {
            VStack(spacing: 10) {
                Text(CurrencyFormatter.string(from: transaction.amount, currencyCode: transaction.currencyCode))
                    .font(.system(.largeTitle, design: .rounded).weight(.bold).monospacedDigit())
                    .foregroundStyle(amountColor)
                    .contentTransition(.numericText())

                HStack(spacing: 8) {
                    Label(transaction.type.displayName, systemImage: typeIcon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(amountColor)
                    if let category = transaction.category {
                        categoryChip(category)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
        }
    }

    private func categoryChip(_ category: TransactionCategory) -> some View {
        HStack(spacing: 5) {
            Image(systemName: category.iconName)
            Text(category.parent.map { "\($0.name) › \(category.name)" } ?? category.name)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(chipColor(category).opacity(0.18), in: Capsule())
        .foregroundStyle(chipColor(category))
    }

    // MARK: - Lokasi (bukti fitur bekerja)

    private func locationSection(_ coordinate: CLLocationCoordinate2D) -> some View {
        Section("Lokasi") {
            Map(initialPosition: .region(MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
            ))) {
                Marker(placeLabel, coordinate: coordinate)
                    .tint(amountColor)
            }
            .allowsHitTesting(false)  // thumbnail statis; tak berebut scroll List
            .frame(height: 170)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 4, trailing: 8))
            .accessibilityLabel("Lokasi transaksi: \(placeLabel)")

            if !transaction.placeName.isEmpty {
                Label(transaction.placeName, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
            }
        }
    }

    // MARK: - Resi

    private func receiptSection(_ image: UIImage) -> some View {
        Section("Resi") {
            Button {
                isReceiptEnlarged = true
            } label: {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 220)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Gambar resi, ketuk untuk memperbesar")
        }
    }

    // MARK: - Metadata

    private var metadataSection: some View {
        Section {
            metaRow("calendar", transaction.date.formatted(.dateTime.weekday(.wide).day().month(.wide).year().hour().minute()))
            if !transaction.merchant.isEmpty {
                metaRow("storefront", transaction.merchant)
            }
            if !transaction.note.isEmpty {
                metaRow("text.alignleft", transaction.note)
            }
            metaRow(sourceIcon, sourceLabel, tint: .secondary)
            if !transaction.rawInput.isEmpty {
                metaRow("quote.opening", "“\(transaction.rawInput)”", italic: true)
            }
        }
    }

    private func metaRow(_ icon: String, _ text: String, tint: Color = .secondary, italic: Bool = false) -> some View {
        Label {
            Text(text).italic(italic)
        } icon: {
            Image(systemName: icon).foregroundStyle(tint)
        }
        .font(.subheadline)
    }

    // MARK: - Turunan

    private var coordinate: CLLocationCoordinate2D? {
        guard let lat = transaction.latitude, let lon = transaction.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private var receiptImage: UIImage? {
        transaction.receiptImageData.flatMap(UIImage.init(data:))
    }

    private var placeLabel: String {
        transaction.placeName.isEmpty ? transaction.merchant : transaction.placeName
    }

    private var amountColor: Color {
        switch transaction.type {
        case .expense: .red
        case .income: .green
        case .transfer: .blue
        }
    }

    private var typeIcon: String {
        switch transaction.type {
        case .expense: "arrow.up.circle.fill"
        case .income: "arrow.down.circle.fill"
        case .transfer: "arrow.left.arrow.right.circle.fill"
        }
    }

    private func chipColor(_ category: TransactionCategory) -> Color {
        category.colorHex.isEmpty ? .accentColor : Color(hex: category.colorHex)
    }

    private var sourceIcon: String {
        switch transaction.source {
        case .manual: "hand.tap"
        case .quickAdd: "square.and.pencil"
        case .appIntent: "mic"
        case .voice: "waveform"
        case .receipt: "doc.viewfinder"
        case .batch: "list.bullet"
        }
    }

    private var sourceLabel: String {
        switch transaction.source {
        case .manual: "Manual"
        case .quickAdd: "Text Entry"
        case .appIntent: "Siri / Pintasan"
        case .voice: "Suara"
        case .receipt: "Resi"
        case .batch: "Batch"
        }
    }
}

/// Penampil resi layar penuh dengan zoom (HIG: gambar bisa diperbesar).
private struct ReceiptViewer: View {
    let image: UIImage
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView([.horizontal, .vertical]) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            }
            .background(Color.black)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Tutup") { onClose() }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}
