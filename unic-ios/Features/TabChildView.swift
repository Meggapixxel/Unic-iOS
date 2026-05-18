import SwiftUI

/// Contract for tab-root screens. Each conforming view exposes its navigation title and toolbar items
/// so `MainView` can wire them directly onto the root `NavigationStack`, bypassing the SwiftUI
/// limitation where `TabView` doesn't propagate `navigationTitle` / `toolbar` preferences upward.
protocol TabChildView: View {
    associatedtype TabToolbarBody: ToolbarContent
    var tabTitle: String { get }
    @ToolbarContentBuilder var tabToolbar: TabToolbarBody { get }
}
