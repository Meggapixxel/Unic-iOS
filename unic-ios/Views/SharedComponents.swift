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

/// Formats a plan period as "d MMMM – d MMMM yyyy" (e.g. "1 May – 31 May 2026").
func planPeriodString(from start: Date, to end: Date) -> String {
    "\(_planDayMonthFmt.string(from: start)) – \(_planDayMonthYearFmt.string(from: end))"
}

/// Formats a single date as "d MMMM yyyy" (e.g. "31 May 2026").
func planDateString(_ date: Date) -> String {
    _planDayMonthYearFmt.string(from: date)
}


// MARK: - Sync Date Label

/// Trailing label that shows a spinner while loading or the last-synced date and time otherwise.
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

/// Full-screen semi-transparent overlay with a spinner and optional status text.
struct LoadingOverlay: View {
    /// Status text shown below the spinner; defaults to a generic "Loading…" string.
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

/// Versatile KPI card supporting both a standard (left-aligned) and compact (centered) layout.
struct StatCard: View {
    /// The formatted metric value (e.g. a currency string or count).
    let value: String
    let label: String
    let icon: String
    let color: Color
    /// When `true`, uses a compact centered layout suited for narrow columns.
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

/// The two sub-tabs available in the Sales feature.
enum SalesSection: String, CaseIterable {
    case analytics, invoices
    var label: String {
        switch self {
        case .analytics: return String.sales_analytics
        case .invoices:  return String.sales_invoices
        }
    }
}

/// Granularity options for the sales analytics period picker.
enum SalesPeriod: String, CaseIterable {
    case month = "month"; case year = "year"
    var displayName: String {
        switch self { case .month: return String.period_month; case .year: return String.period_year }
    }
    /// Computes the calendar-aligned date range for the period that contains `date`.
    /// The upper bound is capped at `now` so future dates are excluded from aggregations.
    /// - Parameter date: Any date within the desired period.
    /// - Returns: The inclusive start and end timestamps.
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

/// Wraps one or more PDF files to be shared via `UIActivityViewController`.
struct PDFShareItem: Identifiable {
    let id = UUID()
    /// The PDF files included in the share, each with its intended filename.
    let files: [(data: Data, filename: String)]

    init(data: Data, filename: String) { files = [(data, filename)] }
    init(files: [(data: Data, filename: String)]) { self.files = files }

    /// Writes each file to the temp directory and returns their URLs for the share sheet.
    var tempURLs: [URL] {
        files.compactMap { file in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(file.filename)
            try? file.data.write(to: url)
            return url
        }
    }
}

/// SwiftUI wrapper around `UIActivityViewController` for sharing `PDFShareItem` files.
struct ShareSheet: UIViewControllerRepresentable {
    let item: PDFShareItem
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: item.tempURLs, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - Sync Status Row

/// Compact inline row showing a sync spinner and the last-synced timestamp.
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

/// Sort options available in the salon list screen.
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

/// Rounded-rectangle badge displaying the lead temperature letter (A/B/C) with color feedback.
struct LeadTempBadge: View {
    let temp: LeadTemp
    /// Whether this badge is the currently selected temperature.
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

/// Navigation row for the Test Drive section, showing a flask icon and the active test-drive count.
struct TestDriveListRow: View {
    /// Number of active test drives.
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

/// Labeled container for a group of filter controls, using a small-caps section header.
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

/// A tappable row with a checkmark circle indicator, used inside `FilterSection`.
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

/// Fields by which the stock list can be sorted.
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

/// Small vertical badge showing a numeric value with animated transitions and a label below it.
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

/// Pill-shaped toggle chip used in filter bars.
/// - Parameters:
///   - title: Label text.
///   - isSelected: Whether the chip is active.
///   - color: Accent color when selected. Defaults to `.accentColor`.
///   - action: Called when the chip is tapped.
struct FilterChip: View {
    let title: String
    let isSelected: Bool
    var color: Color = .accentColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? color : Color(.systemGray5), in: Capsule())
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

/// Horizontally scrolling chip row for salon status filtering with a "?" info button.
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

/// Standard list row for a salon showing name, status badge, address, and contact icons.
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

/// Vertical icon + label action button with a tinted rounded background.
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

/// Bold section header label styled with primary foreground color.
struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title).font(.headline).foregroundColor(.primary)
    }
}

// MARK: - StatusHistoryRow

/// Card-style row showing a status-history entry's status color, name, date, and optional note.
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

/// Modal sheet for editing the note on a status-history entry, presented at `.medium` detent.
struct EditNoteSheet: View {
    let entry: StatusHistoryEntry
    @Binding var isPresented: Bool
    /// Called when the user taps the checkmark, with the trimmed note text (or `nil` if empty).
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
            .navigationInlineTitle(String.note_optional)
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

/// Capsule badge displaying a payment status label with the corresponding color.
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

/// Full-screen reference sheet listing all salon statuses with descriptions and next-action prompts.
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
            .navigationInlineTitle("salon_statuses")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CloseButton { isPresented = false }
                }
            }
        }
    }
}

// MARK: - Glass Effect

/// View modifier that applies a glass effect on iOS 26+ or falls back to ultra-thin material.
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
    /// Applies `GlassBackgroundModifier` with the given shape.
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

/// Standardized `xmark.circle.fill` button used in toolbars and overlays to dismiss a modal.
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

// MARK: - Avatar Circle

/// Circular avatar showing initials or a short label, used for users and map annotations.
struct AvatarCircle: View {
    let text: String
    let color: Color
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.15))
                .frame(width: size, height: size)
            Text(text)
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(color)
        }
    }
}

// MARK: - StatusBadge

/// Rounded badge showing a salon's current status name with the corresponding color.
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

/// Generic error state view with an orange warning icon, message text, and a retry button.
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

/// Main-actor singleton that wraps `CLLocationManager` and exposes one-shot async location fetches.
@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationManager()
    private let manager = CLLocationManager()
    /// The current Core Location authorization status.
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

    /// Requests a single location update and returns the coordinate, or `nil` if unauthorized or failed.
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

/// `MKAnnotation` subclass that carries a `Salon` so the map delegate can reference it on selection.
final class SalonAnnotation: NSObject, MKAnnotation {
    let salon: Salon
    let coordinate: CLLocationCoordinate2D
    init(salon: Salon, coordinate: CLLocationCoordinate2D) {
        self.salon = salon; self.coordinate = coordinate
    }
    var title: String? { salon.displayName }
}

// MARK: - SalonNativeMapView

/// `UIViewRepresentable` wrapping `MKMapView` with clustering, callout detail buttons, and a
/// navigation shortcut that opens Google Maps or Apple Maps.
struct SalonNativeMapView: UIViewRepresentable {
    let salons: [Salon]
    /// Called when the user taps the detail-disclosure button in a salon callout.
    let onSelect: (Salon) -> Void
    /// When set to `true` the map switches to user-tracking mode and then resets the binding to `false`.
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

/// Stock list row showing product code, name, optional volume badge, a color-coded quantity badge, and price.
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
        Text((item.sellPriceVAT).czk)
            .font(.caption.bold())
            .foregroundStyle(.primary)
    }
}

// MARK: - Client Form Fields

/// Reusable set of form fields for creating or editing a client (firm).
/// Used in both ClientEditView and CreateClientView.
struct ClientFormFields: View {
    @Binding var name: String
    @Binding var ic: String
    @Binding var dic: String
    @Binding var email: String
    @Binding var phone: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "building.2.fill")
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)
            TextField(String.create_client_name_placeholder, text: $name)
                .autocorrectionDisabled()
        }
        HStack(spacing: 12) {
            Image(systemName: "number")
                .foregroundStyle(.secondary)
                .frame(width: 20)
            TextField("IČO", text: $ic)
                .keyboardType(.numberPad)
        }
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
                .frame(width: 20)
            TextField("DIČ", text: $dic)
                .autocorrectionDisabled()
                .autocapitalization(.allCharacters)
        }
        HStack(spacing: 12) {
            Image(systemName: "envelope")
                .foregroundStyle(.secondary)
                .frame(width: 20)
            TextField("info@company.cz", text: $email)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
                .autocapitalization(.none)
        }
        HStack(spacing: 12) {
            Image(systemName: "phone")
                .foregroundStyle(.secondary)
                .frame(width: 20)
            TextField("+420 123 456 789", text: $phone)
                .keyboardType(.phonePad)
        }
    }
}

// MARK: - Invoice Timeline Components

/// A single icon + label step in the invoice timeline, springs in on first appearance.
struct InvoiceTimelineStep: View {
    let icon: String
    let label: String
    /// Whether this stage has been completed.
    let done: Bool
    /// Delay (in seconds) before the spring entrance animation fires.
    let delay: Double

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(done ? Color.green : Color(.systemGray3))
                .symbolEffect(.bounce, value: done)
                .animation(.easeInOut(duration: 0.35), value: done)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(done ? Color.green : Color(.systemGray3))
                .animation(.easeInOut(duration: 0.35), value: done)
        }
        .frame(minWidth: 44)
        .scaleEffect(appeared ? 1 : 0.5)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.65).delay(delay)) {
                appeared = true
            }
        }
    }
}

/// Horizontal line between two timeline steps; fills with green when the preceding stage is complete.
struct InvoiceTimelineConnector: View {
    /// Whether the preceding stage is complete, causing the line to animate to full width.
    let done: Bool
    /// Delay (in seconds) before the fade-in animation fires.
    let delay: Double

    @State private var appeared = false

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color(.systemGray4))
                .frame(height: 2)
            Rectangle()
                .fill(Color.green)
                .frame(height: 2)
                .scaleEffect(x: done ? 1 : 0, anchor: .leading)
                .animation(.easeInOut(duration: 0.4), value: done)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 18)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.easeIn(duration: 0.25).delay(delay)) {
                appeared = true
            }
        }
    }
}

extension View {
    func navigationInlineTitle(_ title: String) -> some View {
        self
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}
