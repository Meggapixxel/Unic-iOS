// FILE: unic-ios/Features/Stock/CatalogFeature.swift

import ComposableArchitecture
import PDFKit
import SwiftUI

// MARK: - Feature

@Reducer
struct CatalogFeature {
    @ObservableState
    struct State: Equatable {
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

private struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - PDFKit bridge

private struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.document = PDFDocument(url: url)
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}
}
