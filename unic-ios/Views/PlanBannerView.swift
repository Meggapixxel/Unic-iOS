import Combine
import ComposableArchitecture
import SwiftUI

// MARK: - Plan ViewModel (used in MainScreen)

/// MVVM view model that fetches the active plan from Firebase and tracks whether the banner has been dismissed.
@MainActor
final class PlanViewModel: ObservableObject {
    /// The currently active plan, or `nil` if no plan is running.
    @Published var activePlan: Plan?
    /// Whether the user has dismissed the banner for this session.
    @Published var isDismissed = false

    private let service = FirebaseService.shared
    private var tasks: [Task<Void, Never>] = []

    /// Starts an async task to fetch the active plan; subsequent calls before the task completes are tracked.
    func load() {
        let task = Task {
            do {
                activePlan = try await service.fetchActivePlan()
            } catch {}
        }
        tasks.append(task)
    }

    /// Cancels all in-flight tasks (call on view disappear or deinit).
    func cancel() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }

    /// `true` when there is an active plan and the user has not dismissed the banner.
    var shouldShow: Bool {
        guard let plan = activePlan, plan.isActive else { return false }
        return !isDismissed
    }
}

// MARK: - Plan Banner View (MVVM — used in MainScreen)

/// Collapsible plan banner driven by `PlanViewModel`; hides itself when dismissed or when no plan is active.
struct PlanBannerView: View {
    @ObservedObject var viewModel: PlanViewModel
    @State private var isExpanded = false

    var body: some View {
        if let plan = viewModel.activePlan, viewModel.shouldShow {
            _PlanBannerContent(plan: plan, isExpanded: $isExpanded) {
                withAnimation { viewModel.isDismissed = true }
            }
        }
    }
}

// MARK: - Plan Banner View (TCA — used in MainView)

/// TCA-backed variant of the plan banner; reads plan state from a `PlanBannerFeature` store.
struct TCAPlankBannerView: View {
    let store: StoreOf<PlanBannerFeature>
    @State private var isExpanded = false
    /// Local dismissal flag; not persisted, resets when the view is recreated.
    @State private var isDismissed = false

    var body: some View {
        if let plan = store.plan, store.shouldShow, !isDismissed {
            _PlanBannerContent(plan: plan, isExpanded: $isExpanded) {
                withAnimation { isDismissed = true }
            }
            .onAppear { store.send(.load) }
        }
    }
}

// MARK: - Shared content

/// Internal banner body shared between `PlanBannerView` and `TCAPlankBannerView`.
private struct _PlanBannerContent: View {
    let plan: Plan
    @Binding var isExpanded: Bool
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "target")
                        .foregroundStyle(.white)
                        .font(.subheadline.bold())
                    Text(planPeriodString(from: plan.startDate, to: plan.endDate))
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.white.opacity(0.8))
                        .font(.caption.bold())
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.caption.bold())
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(6)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

        }
        .background(Color.accentColor.gradient)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.accentColor.opacity(0.3), radius: 8, y: 4)
        .padding(.horizontal)
        .padding(.top, 8)
    }
}
