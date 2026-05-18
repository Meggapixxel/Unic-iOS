// FILE: unic-ios/Features/Stock/CatalogFeature.swift

import ComposableArchitecture
import PDFKit
import SwiftUI

// MARK: - Feature

/// Backs the in-app PDF catalog viewer screen; its sole responsibility is toggling the system
/// share sheet that lets users export the bundled `catalog.pdf` file.
///
/// **Entry point**
/// Pushed onto `StockFeature`'s `NavigationStack` path via `.openCatalog`. No async loading
/// is required — the PDF is read from the app bundle synchronously inside `PDFKitView`.
///
/// **Key action flows**
/// - `.shareTapped` — sets `isSharing = true`, which triggers the `CatalogView` sheet binding
///   to present a `UIActivityViewController` wrapping the bundle PDF URL.
/// - `.shareCompleted` — resets `isSharing = false` when the share sheet is dismissed.
///
/// **Navigation**
/// No `Path` or `Destination` reducers. The share sheet is driven entirely by the `isSharing`
/// boolean state bound to a `.sheet` modifier in `CatalogView`.
///
/// **Side effects**
/// None — the PDF is loaded from the app bundle on a background `DispatchQueue` inside
/// `PDFKitView.makeUIView`, entirely outside the TCA effect system.
@Reducer
struct CatalogFeature {
    /// Observable state for the catalog viewer.
    @ObservableState
    struct State: Equatable {
        /// `true` while the system share sheet is being displayed.
        var isSharing: Bool = false
    }

    enum Action {
        case shareTapped
        case shareCompleted
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .shareTapped:
                state.isSharing = true
                return .none
            case .shareCompleted:
                state.isSharing = false
                return .none
            }
        }
    }
}

// MARK: - View

/// View displaying the bundled `catalog.pdf` via PDFKit with a share toolbar button.
struct CatalogView: View {
    @Bindable var store: StoreOf<CatalogFeature>

    var body: some View {
        Group {
            if let url = Bundle.main.url(forResource: "catalog", withExtension: "pdf") {
                PDFKitView(url: url)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                ContentUnavailableView(
                    String.catalog_unavailable,
                    systemImage: "doc.fill"
                )
            }
        }
        .navigationTitle(String.catalog_nav_title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    store.send(.shareTapped)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .sheet(
            isPresented: Binding(
                get: { store.isSharing },
                set: { if !$0 { store.send(.shareCompleted) } }
            )
        ) {
            if let url = Bundle.main.url(forResource: "catalog", withExtension: "pdf") {
                ActivitySheet(items: [url])
                    .ignoresSafeArea()
            }
        }
    }
}

// MARK: - Activity Sheet (generic URL share)

/// `UIViewControllerRepresentable` wrapper presenting `UIActivityViewController` for a list of shareable items.
private struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - PDFKit bridge

/// `UIViewRepresentable` that loads and displays a PDF document from a file URL using `PDFView`.
private struct PDFKitView: UIViewRepresentable {
    let url: URL

    /// Creates a `PDFView` configured for vertical continuous scrolling, then loads the document on a background thread.
    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        let url = url
        DispatchQueue.global(qos: .userInitiated).async {
            let document = PDFDocument(url: url)
            DispatchQueue.main.async {
                pdfView.document = document
            }
        }
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}
}
