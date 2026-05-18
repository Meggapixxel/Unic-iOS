import ComposableArchitecture
import SwiftUI

/// List view for all plans, with swipe-to-delete/edit actions and a sheet for creating or modifying plans.
struct PlansView: View {
    @Bindable var store: StoreOf<PlansFeature>

    var body: some View {
        List {
            ForEach(store.plans, id: \.id) { plan in
                PlanRow(plan: plan)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if store.canManagePlans {
                            store.send(.editTapped(plan))
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        if store.canManagePlans {
                            Button(role: .destructive) {
                                store.send(.deleteTapped(plan))
                            } label: {
                                Label(String.plan_delete, systemImage: "trash")
                            }
                        }
                    }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(String.plans_nav_title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if store.canManagePlans {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { store.send(.addTapped) } label: { Image(systemName: "plus") }
                }
            }
        }
        .overlay {
            if store.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
            } else if store.plans.isEmpty {
                ContentUnavailableView(String.plans_empty, systemImage: "target")
            }
        }
        .alert(String.error, isPresented: Binding(
            get: { store.error != nil },
            set: { _ in store.send(.binding(.set(\.error, nil))) }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            if let err = store.error { Text(err) }
        }
        .confirmationDialog(
            String.plan_delete_confirm,
            isPresented: Binding(
                get: { store.pendingDeletePlan != nil },
                set: { if !$0 { store.send(.cancelDelete) } }
            ),
            titleVisibility: .visible
        ) {
            Button(String.plan_delete, role: .destructive) { store.send(.deleteConfirmed) }
            Button(String.cancel, role: .cancel) { store.send(.cancelDelete) }
        }
        .sheet(
            item: $store.scope(state: \.destination?.form, action: \.destination.form)
        ) { formStore in
            PlansFormView(store: formStore)
        }
        .task { store.send(.onLoad) }
    }
}

// MARK: - PlansFormView

/// Modal form for creating a new plan or editing an existing one, presented as a sheet from ``PlansView``.
struct PlansFormView: View {
    @Bindable var store: StoreOf<PlansFormFeature>

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(String.plan_start_date, selection: $store.startDate, displayedComponents: .date)
                    DatePicker(String.plan_end_date, selection: $store.endDate, in: store.startDate..., displayedComponents: .date)
                }
                Section(String.plan_goal_per_day) {
                    Stepper(value: $store.salonsPerDay, in: 0...99) {
                        HStack {
                            Label(String.plan_target_salons, systemImage: "storefront")
                            Spacer()
                            Text("\(store.salonsPerDay)").foregroundStyle(.secondary)
                        }
                    }
                    Stepper(value: $store.testDrivesPerDay, in: 0...99) {
                        HStack {
                            Label(String.plan_target_test_drives, systemImage: "car.side")
                            Spacer()
                            Text("\(store.testDrivesPerDay)").foregroundStyle(.secondary)
                        }
                    }
                }
                Section(String.plan_goal_total) {
                    Stepper(value: $store.salonsTotal, in: 0...999) {
                        HStack {
                            Label(String.plan_target_salons, systemImage: "storefront")
                            Spacer()
                            Text("\(store.salonsTotal)").foregroundStyle(.secondary)
                        }
                    }
                    Stepper(value: $store.testDrivesTotal, in: 0...999) {
                        HStack {
                            Label(String.plan_target_test_drives, systemImage: "car.side")
                            Spacer()
                            Text("\(store.testDrivesTotal)").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(store.isEditing ? String.plan_edit : String.plan_add)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseButton { store.send(.cancelTapped) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { store.send(.saveTapped) } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(!store.isValid || store.isSaving)
                }
            }
            .overlay {
                if store.isSaving {
                    ProgressView()
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                }
            }
            .alert(String.error, isPresented: Binding(
                get: { store.error != nil },
                set: { _ in store.send(.binding(.set(\.error, nil))) }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                if let err = store.error { Text(err) }
            }
        }
    }
}

// MARK: - Plan Row

/// A single row in the plans list showing the period, duration, per-day/total targets, and an active/done/upcoming badge.
private struct PlanRow: View {
    let plan: Plan

    /// Formatted date-range string for the plan's start and end dates.
    private var period: String { planPeriodString(from: plan.startDate, to: plan.endDate) }

    /// Number of calendar days covered by the plan, with a minimum of 1.
    private var durationDays: Int {
        max(1, Calendar.current.dateComponents([.day], from: plan.startDate, to: plan.endDate).day ?? 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(period)
                    .font(.headline)
                Spacer()
                statusBadge
            }

            HStack(spacing: 0) {
                Text("\(durationDays) \(String.day_abbr)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                let hasSalons = plan.targetSalonsPerDay > 0 || (plan.targetSalons ?? 0) > 0
                let hasTestDrives = plan.targetTestDrivesPerDay > 0 || (plan.targetTestDrives ?? 0) > 0

                if hasSalons {
                    Text("  ·  ").font(.caption).foregroundStyle(.tertiary)
                    targetChip(icon: "storefront", perDay: plan.targetSalonsPerDay, total: plan.targetSalons)
                }
                if hasTestDrives {
                    Text("  ·  ").font(.caption).foregroundStyle(.tertiary)
                    targetChip(icon: "car.side", perDay: plan.targetTestDrivesPerDay, total: plan.targetTestDrives)
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// Inline chip showing a metric icon, optional per-day target, and optional period total.
    /// - Parameters:
    ///   - icon: SF Symbol name for the metric type.
    ///   - perDay: Daily target; omitted from display when zero.
    ///   - total: Period total target; omitted from display when nil or zero.
    @ViewBuilder
    private func targetChip(icon: String, perDay: Int, total: Int?) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
            if perDay > 0 {
                Text("\(perDay)/\(String.day_abbr)")
            }
            if let t = total, t > 0 {
                Text("(\(t))")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }

    /// Badge indicating whether the plan is currently active, already past, or upcoming.
    @ViewBuilder
    private var statusBadge: some View {
        if plan.isActive {
            Text("● \(String.plan_status_active)").font(.caption.bold()).foregroundStyle(.green)
        } else if plan.isPast {
            Text("✓ \(String.plan_status_done)").font(.caption).foregroundStyle(.secondary)
        } else {
            Text("◌ \(String.plan_status_upcoming)").font(.caption).foregroundStyle(.orange)
        }
    }
}
