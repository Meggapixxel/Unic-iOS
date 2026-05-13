import SwiftUI

// MARK: - Plan ViewModel (used in MainScreen)

@MainActor
final class PlanViewModel: ObservableObject {
    @Published var activePlan: Plan?
    @Published var isDismissed = false

    private let service = FirebaseService.shared
    private var tasks: [Task<Void, Never>] = []

    func load() {
        let task = Task {
            do {
                activePlan = try await service.fetchActivePlan()
            } catch {}
        }
        tasks.append(task)
    }

    func cancel() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }

    var shouldShow: Bool {
        guard let plan = activePlan, plan.isActive else { return false }
        return !isDismissed
    }
}

// MARK: - Plan Banner View

struct PlanBannerView: View {
    @ObservedObject var viewModel: PlanViewModel
    @State private var isExpanded = false

    var body: some View {
        if let plan = viewModel.activePlan, viewModel.shouldShow {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.spring(response: 0.3)) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "target")
                            .foregroundStyle(.white)
                            .font(.subheadline.bold())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(plan.title)
                                .font(.subheadline.bold())
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text("\(String(localized: "plan_active_until")) \(plan.endDate.formatted(.dateTime.day().month(.abbreviated)))")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        Spacer()
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .foregroundStyle(.white.opacity(0.8))
                            .font(.caption.bold())
                        Button {
                            withAnimation { viewModel.isDismissed = true }
                        } label: {
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

                if isExpanded {
                    Text(plan.description)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .background(Color.accentColor.gradient)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: Color.accentColor.opacity(0.3), radius: 8, y: 4)
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }
}
