import SwiftUI
import MapKit
import CoreLocation
import Combine

// MARK: - Date Formatters

private let _planDayMonthFmt: DateFormatter = {
    let f = DateFormatter(); f.dateFormat = "d MMMM"; return f
}()
private let _planDayMonthYearFmt: DateFormatter = {
    let f = DateFormatter(); f.dateFormat = "d MMMM yyyy"; return f
}()

func planPeriodString(from start: Date, to end: Date) -> String {
    "\(_planDayMonthFmt.string(from: start)) – \(_planDayMonthYearFmt.string(from: end))"
}

func planDateString(_ date: Date) -> String {
    _planDayMonthYearFmt.string(from: date)
}

// MARK: - CZK Formatter

private extension NumberFormatter {
    static let czk: NumberFormatter = {
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.currencyCode = "CZK"
        fmt.maximumFractionDigits = 0
        return fmt
    }()
}

func czk(_ amount: Double) -> String {
    guard amount > 0 else { return "—" }
    return NumberFormatter.czk.string(from: NSNumber(value: amount)) ?? "\(Int(amount)) Kč"
}

// MARK: - Sync Date Label

struct SyncDateLabel: View {
    let isLoading: Bool
    let lastSyncDate: Date?

    var body: some View {
        if isLoading {
            ProgressView().scaleEffect(0.8)
        } else {
            VStack(alignment: .trailing, spacing: 1) {
                Text(lastSyncDate.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? String.never)
                    .font(.caption2).foregroundStyle(.secondary)
                Text(lastSyncDate.map { $0.formatted(date: .omitted, time: .shortened) } ?? "")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - Loading Overlay

struct LoadingOverlay: View {
    var text: String = String.loading

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(text).font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.15))
    }
}

// MARK: - Stat Card (unified KPICard + MiniStatsCard)

struct StatCard: View {
    let value: String
    let label: String
    let icon: String
    let color: Color
    var compact: Bool = false

    var body: some View {
        VStack(alignment: compact ? .center : .leading, spacing: compact ? 5 : 8) {
            Image(systemName: icon).font(.title3).foregroundStyle(color)
            Text(value)
                .font(.title3.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(compact ? .caption2 : .caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: compact ? .center : .leading)
        .padding(compact ? .vertical : .all, 12)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Stock Row

// MARK: - Sales Enums

enum SalesSection: String, CaseIterable {
    case analytics, invoices
    var label: String {
        switch self {
        case .analytics: return String.sales_analytics
        case .invoices:  return String.sales_invoices
        }
    }
}

enum SalesPeriod: String, CaseIterable {
    case month = "month"; case year = "year"
    var displayName: String {
        switch self { case .month: return String.period_month; case .year: return String.period_year }
    }
    func dateRange(for date: Date) -> (from: Date, to: Date) {
        let cal = Calendar.current; let now = Date()
        switch self {
        case .month:
            let start = cal.date(from: cal.dateComponents([.year, .month], from: date))!
            let nextStart = cal.date(byAdding: .month, value: 1, to: start)!
            return (start, min(nextStart.addingTimeInterval(-1), now))
        case .year:
            let year = cal.component(.year, from: date)
            let start = cal.date(from: DateComponents(year: year, month: 1, day: 1))!
            let nextStart = cal.date(from: DateComponents(year: year + 1, month: 1, day: 1))!
            return (start, min(nextStart.addingTimeInterval(-1), now))
        }
    }
}

// MARK: - PDFShareItem

struct PDFShareItem: Identifiable {
    let id = UUID()
    let files: [(data: Data, filename: String)]

    init(data: Data, filename: String) { files = [(data, filename)] }
    init(files: [(data: Data, filename: String)]) { self.files = files }

    var tempURLs: [URL] {
        files.compactMap { file in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(file.filename)
            try? file.data.write(to: url)
            return url
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let item: PDFShareItem
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: item.tempURLs, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - Sync Status Row

struct SyncStatusRow: View {
    let isLoading: Bool
    let lastSyncDate: Date?

    var body: some View {
        HStack(spacing: 6) {
            if isLoading {
                ProgressView().scaleEffect(0.7)
                Text(String.loading)
            } else {
                Image(systemName: "arrow.clockwise")
                    .font(.caption2)
                if let date = lastSyncDate {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                } else {
                    Text(String.never)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}

// MARK: - SalonSortOption

enum SalonSortOption: String, CaseIterable, Identifiable {
    case name = "name"; case leadTemp = "leadTemp"; case status = "status"; case dateAdded = "dateAdded"
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .name:      return String.sort_by_name
        case .leadTemp:  return String.sort_by_lead_temp
        case .status:    return String.sort_by_status
        case .dateAdded: return String.sort_by_date
        }
    }
}

// MARK: - LeadTemp UI Extensions

extension LeadTemp {
    var color: Color {
        switch self {
        case .A: return .red
        case .B: return .orange
        case .C: return .blue
        }
    }
    var title: String {
        switch self { case .A: return String.lead_temp_a; case .B: return String.lead_temp_b; case .C: return String.lead_temp_c }
    }
}

// MARK: - LeadTempBadge

struct LeadTempBadge: View {
    let temp: LeadTemp
    let isSelected: Bool
    var body: some View {
        Text(temp.rawValue)
            .font(.subheadline.bold())
            .frame(width: 32, height: 32)
            .background(isSelected ? temp.color : Color(.systemGray5))
            .foregroundColor(isSelected ? .white : .secondary)
            .cornerRadius(8)
    }
}

// MARK: - TestDriveListRow

struct TestDriveListRow: View {
    let count: Int
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "flask.fill")
                .font(.title2)
                .foregroundStyle(.purple)
                .frame(width: 36, height: 36)
                .background(Color.purple.opacity(0.12))
                .cornerRadius(8)
            VStack(alignment: .leading, spacing: 2) {
                Text(String.test_drive).font(.headline)
                Text("\(count) \(String.stat_total.lowercased())").font(.subheadline).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - FilterSection / FilterRow

struct FilterSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2.uppercaseSmallCaps()).foregroundColor(.secondary)
            content
        }
    }
}

struct FilterRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .font(.subheadline)
                Text(title).font(.subheadline)
                Spacer()
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - StockSortField

enum StockSortField: String, CaseIterable {
    case section, name, quantity
}

// MARK: - SalonStatus UI Extensions

extension SalonStatus {
    var displayName: String {
        switch self {
        case .new: return String.status_new
        case .contacted: return String.status_contacted
        case .demoScheduled: return String.status_demo
        case .testDrive: return String.status_test_drive
        case .ordered: return String.status_ordered
        case .other: return String.status_other
        }
    }

    var color: Color {
        switch self {
        case .new: return .green
        case .contacted: return .orange
        case .demoScheduled: return .blue
        case .testDrive: return .purple
        case .ordered: return .mint
        case .other: return .gray
        }
    }

    var emoji: String {
        switch self {
        case .new: return "🆕"; case .contacted: return "💬"; case .demoScheduled: return "📅"
        case .testDrive: return "🧪"; case .ordered: return "📦"; case .other: return "🔘"
        }
    }

    var fullDisplayName: String {
        switch self {
        case .new: return String.status_new_full; case .contacted: return String.status_contacted_full
        case .demoScheduled: return String.status_demo_full; case .testDrive: return String.status_test_drive_full
        case .ordered: return String.status_ordered_full; case .other: return String.status_other_full
        }
    }

    var infoDescription: String {
        switch self {
        case .new: return String.status_new_desc; case .contacted: return String.status_contacted_desc
        case .demoScheduled: return String.status_demo_desc; case .testDrive: return String.status_test_drive_desc
        case .ordered: return String.status_ordered_desc; case .other: return String.status_other_desc
        }
    }

    var nextAction: String {
        switch self {
        case .new: return String.status_new_action; case .contacted: return String.status_contacted_action
        case .demoScheduled: return String.status_demo_action; case .testDrive: return String.status_test_drive_action
        case .ordered: return String.status_ordered_action; case .other: return String.status_other_action
        }
    }
}

// MARK: - StatBadge

struct StatBadge: View {
    let title: String; let value: Int; let color: Color
    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)").font(.title2.bold()).foregroundColor(color)
                .contentTransition(.numericText()).animation(.snappy, value: value)
            Text(title).font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - FilterChip / FilterChipsView

struct FilterChip: View {
    let title: String; let isSelected: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.subheadline)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(.systemGray5))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(16)
        }
    }
}

struct FilterChipsView: View {
    @Binding var statusOptions: Options<SalonStatus>
    @Binding var showStatusInfo: Bool
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button { showStatusInfo = true } label: {
                    Image(systemName: "questionmark.circle").font(.subheadline).foregroundColor(.secondary)
                        .frame(width: 28, height: 28).background(Color(.systemGray5)).clipShape(Circle())
                }
                FilterChip(title: String.filter_all, isSelected: !statusOptions.hasSelection) { statusOptions.clear() }
                ForEach(statusOptions.all) { status in
                    FilterChip(title: "\(status.emoji) \(status.displayName)", isSelected: statusOptions.isSelected(status)) {
                        statusOptions.toggle(status)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - SalonRowView

struct SalonRowView: View {
    let salon: Salon
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(salon.displayName).font(.headline)
                Spacer()
                StatusBadge(status: salon.statusEnum)
            }
            if let address = salon.address {
                Text(address).font(.subheadline).foregroundColor(.secondary).lineLimit(1)
            }
            HStack(spacing: 8) {
                if salon.phoneNumber != nil { Image(systemName: "phone.fill").font(.caption).foregroundColor(.green) }
                if salon.instagramHandle != nil { Image(systemName: "camera.fill").font(.caption).foregroundColor(.purple) }
                if salon.contacts?.facebook?.value != nil { Image(systemName: "hand.thumbsup.fill").font(.caption).foregroundColor(.blue) }
                if salon.websiteURL != nil { Image(systemName: "globe").font(.caption).foregroundColor(.orange) }
                if let lang = salon.language, !lang.isEmpty { Text(flagEmoji(for: lang)).font(.caption) }
            }
        }
        .padding(.vertical, 4)
    }
}

private func flagEmoji(for languageCode: String) -> String {
    let regionCode: String
    switch languageCode.prefix(2).lowercased() {
    case "uk": regionCode = "UA"; case "ru": regionCode = "RU"; case "cs": regionCode = "CZ"
    case "sk": regionCode = "SK"; case "pl": regionCode = "PL"; case "de": regionCode = "DE"
    default: regionCode = Locale(identifier: languageCode).region?.identifier ?? "UN"
    }
    let base: UInt32 = 127397
    return regionCode.uppercased().unicodeScalars
        .compactMap { Unicode.Scalar(base + $0.value).map(String.init) }.joined()
}

// MARK: - ActionButton

struct ActionButton: View {
    let title: String; let icon: String; let color: Color; let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.title2)
                Text(title).font(.caption)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(color.opacity(0.15)).foregroundColor(color).cornerRadius(12)
        }
    }
}

// MARK: - SectionHeader

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title).font(.headline).foregroundColor(.primary)
    }
}

// MARK: - StatusHistoryRow

struct StatusHistoryRow: View {
    let entry: StatusHistoryEntry
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(entry.statusEnum.color).frame(width: 10, height: 10).padding(.top, 5)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entry.statusEnum.displayName).font(.subheadline.bold())
                    Spacer()
                    Text(entry.formattedDate).font(.caption).foregroundColor(.secondary)
                }
                if let note = entry.note, !note.isEmpty {
                    Text(note).font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 8).padding(.horizontal, 12)
        .background(Color(.systemGray6)).cornerRadius(8)
    }
}

// MARK: - EditNoteSheet

struct EditNoteSheet: View {
    let entry: StatusHistoryEntry
    @Binding var isPresented: Bool
    let onSave: (String?) -> Void
    @State private var noteText: String

    init(entry: StatusHistoryEntry, isPresented: Binding<Bool>, onSave: @escaping (String?) -> Void) {
        self.entry = entry; self._isPresented = isPresented; self.onSave = onSave
        _noteText = State(initialValue: entry.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 8) {
                        Circle().fill(entry.statusEnum.color).frame(width: 10, height: 10)
                        Text(entry.statusEnum.displayName).font(.subheadline.bold())
                        Spacer()
                        Text(entry.formattedDate).font(.caption).foregroundColor(.secondary)
                    }
                }
                Section("note_optional") {
                    TextField(String.add_comment, text: $noteText, axis: .vertical).lineLimit(3...8)
                }
            }
            .navigationTitle(String.note_optional).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { CloseButton { isPresented = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onSave(noteText.trimmingCharacters(in: .whitespacesAndNewlines))
                        isPresented = false
                    } label: { Image(systemName: "checkmark") }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - InvoiceStatusBadge

struct InvoiceStatusBadge: View {
    let status: PaymentStatus
    var body: some View {
        Text(status.label)
            .font(.caption2.bold())
            .foregroundStyle(status.color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(status.color.opacity(0.12), in: Capsule())
    }
}

// MARK: - StatusInfoView

struct StatusInfoView: View {
    @Binding var isPresented: Bool
    var body: some View {
        NavigationStack {
            List {
                ForEach(SalonStatus.allCases) { status in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(status.emoji)
                            Text(status.fullDisplayName).font(.headline)
                        }
                        Text(status.infoDescription).font(.subheadline).foregroundColor(.secondary)
                        Text(status.nextAction).font(.caption).foregroundColor(status.color)
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("salon_statuses")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CloseButton { isPresented = false }
                }
            }
        }
    }
}

// MARK: - Glass Effect

struct GlassBackgroundModifier<S: Shape>: ViewModifier {
    let shape: S
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .shadow(color: .black.opacity(0.1), radius: 10, y: -5)
        }
    }
}

extension View {
    func glassBackground<S: Shape>(in shape: S) -> some View {
        modifier(GlassBackgroundModifier(shape: shape))
    }
    func glassBackgroundCapsule() -> some View { glassBackground(in: Capsule()) }
    func glassBackgroundCircle() -> some View { glassBackground(in: Circle()) }
    func glassBackgroundRectangle(cornerRadius: CGFloat? = nil) -> some View {
        if let r = cornerRadius {
            return AnyView(glassBackground(in: RoundedRectangle(cornerRadius: r)))
        } else {
            return AnyView(glassBackground(in: Rectangle()))
        }
    }
}

// MARK: - CloseButton

struct CloseButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
                .imageScale(.large)
        }
    }
}

// MARK: - StatusBadge

struct StatusBadge: View {
    let status: SalonStatus
    var body: some View {
        Text(status.displayName)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.color.opacity(0.2))
            .foregroundColor(status.color)
            .cornerRadius(8)
    }
}

// MARK: - ErrorView

struct ErrorView: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.orange)
            Text(message).multilineTextAlignment(.center)
            Button("retry", action: retry).buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

// MARK: - LocationManager

@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationManager()
    private let manager = CLLocationManager()
    @Published private(set) var authStatus: CLAuthorizationStatus = .notDetermined
    private var locationContinuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authStatus = manager.authorizationStatus
    }

    func requestPermission() { manager.requestWhenInUseAuthorization() }
    var isAuthorized: Bool { authStatus == .authorizedWhenInUse || authStatus == .authorizedAlways }

    func fetchCurrentLocation() async -> CLLocationCoordinate2D? {
        guard isAuthorized else { return nil }
        return await withCheckedContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated { authStatus = status }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coord = locations.last?.coordinate
        MainActor.assumeIsolated {
            locationContinuation?.resume(returning: coord)
            locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            locationContinuation?.resume(returning: nil)
            locationContinuation = nil
        }
    }
}

// MARK: - SalonAnnotation

final class SalonAnnotation: NSObject, MKAnnotation {
    let salon: Salon
    let coordinate: CLLocationCoordinate2D
    init(salon: Salon, coordinate: CLLocationCoordinate2D) {
        self.salon = salon; self.coordinate = coordinate
    }
    var title: String? { salon.displayName }
}

// MARK: - SalonNativeMapView

struct SalonNativeMapView: UIViewRepresentable {
    let salons: [Salon]
    let onSelect: (Salon) -> Void
    @Binding var centerOnUser: Bool

    private static let annotationId = "SalonPin"
    private static let clusteringIdentifier = "SalonCluster"

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.setRegion(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 50.0755, longitude: 14.4378),
            span: MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
        ), animated: false)
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: Self.annotationId)
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        if centerOnUser {
            map.setUserTrackingMode(.follow, animated: true)
            DispatchQueue.main.async { self.centerOnUser = false }
        }
        let existing = map.annotations.compactMap { $0 as? SalonAnnotation }
        let existingMap = Dictionary(uniqueKeysWithValues: existing.map { ($0.salon.salonId, $0.salon) })
        let newMapped = salons.filter { $0.coordinate != nil }
        let existingIds = Set(existingMap.keys)
        let newIds = Set(newMapped.map { $0.salonId })
        let dataChanged = newMapped.contains { existingMap[$0.salonId] != $0 }
        if existingIds == newIds && !dataChanged { return }
        map.removeAnnotations(existing)
        let annotations = newMapped.compactMap { salon -> SalonAnnotation? in
            guard let c = salon.coordinate else { return nil }
            return SalonAnnotation(salon: salon, coordinate: c)
        }
        map.addAnnotations(annotations)
    }

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }

    final class Coordinator: NSObject, MKMapViewDelegate {
        let onSelect: (Salon) -> Void
        init(onSelect: @escaping (Salon) -> Void) { self.onSelect = onSelect }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            if let cluster = annotation as? MKClusterAnnotation {
                guard let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier, for: cluster
                ) as? MKMarkerAnnotationView else { return nil }
                view.markerTintColor = .systemGray; view.titleVisibility = .adaptive; view.canShowCallout = false
                return view
            }
            guard let ann = annotation as? SalonAnnotation,
                  let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: SalonNativeMapView.annotationId, for: ann
                  ) as? MKMarkerAnnotationView else { return nil }
            view.markerTintColor = UIColor(ann.salon.statusEnum.color)
            view.glyphImage = nil; view.glyphText = nil; view.titleVisibility = .hidden
            view.clusteringIdentifier = SalonNativeMapView.clusteringIdentifier
            view.displayPriority = .defaultLow; view.canShowCallout = true
            let detailBtn = UIButton(type: .detailDisclosure)
            view.leftCalloutAccessoryView = detailBtn
            let navBtn = UIButton(type: .system)
            navBtn.setImage(UIImage(systemName: "arrow.triangle.turn.up.right.circle.fill"), for: .normal)
            navBtn.tintColor = UIColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1)
            navBtn.sizeToFit(); view.rightCalloutAccessoryView = navBtn
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            if let cluster = annotation as? MKClusterAnnotation {
                mapView.deselectAnnotation(annotation, animated: false)
                var region = mapView.region
                region.span.latitudeDelta /= 3; region.span.longitudeDelta /= 3
                region.center = cluster.coordinate
                mapView.setRegion(region, animated: true)
            }
        }

        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView,
                     calloutAccessoryControlTapped control: UIControl) {
            guard let ann = view.annotation as? SalonAnnotation else { return }
            if control == view.leftCalloutAccessoryView {
                mapView.deselectAnnotation(ann, animated: true); onSelect(ann.salon)
            } else if control == view.rightCalloutAccessoryView {
                let coord = ann.coordinate
                let name = ann.salon.displayName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                let googleUrl = URL(string: "comgooglemaps://?daddr=\(coord.latitude),\(coord.longitude)&directionsmode=driving")
                let appleUrl = URL(string: "maps://?daddr=\(coord.latitude),\(coord.longitude)&q=\(name)")
                if let google = googleUrl, UIApplication.shared.canOpenURL(google) {
                    UIApplication.shared.open(google)
                } else if let apple = appleUrl { UIApplication.shared.open(apple) }
            }
        }
    }
}

// MARK: - Salon.coordinate

extension Salon {
    var coordinate: CLLocationCoordinate2D? {
        guard let location = maps?.location else { return nil }
        return CLLocationCoordinate2D(latitude: location.lat, longitude: location.lng)
    }
}

// MARK: - StockWithPriceRow

struct StockWithPriceRow: View {
    let item: FlexiBeeStockItem

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.code)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Text(item.productName)
                    .font(.callout)
                    .lineLimit(2)
                if let vol = item.volume {
                    Text(vol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.systemGray5), in: Capsule())
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                quantityBadge
                if item.sellPriceVAT > 0 { priceInfo }
            }
        }
        .padding(.vertical, 2)
    }

    private var quantityBadge: some View {
        let color: Color = item.quantity <= 0 ? .red : item.quantity <= 2 ? .orange : .green
        return Text(String.sales_quantity(Int(item.quantity)))
            .font(.subheadline.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var priceInfo: some View {
        Text(czk(item.sellPriceVAT))
            .font(.caption.bold())
            .foregroundStyle(.primary)
    }
}
