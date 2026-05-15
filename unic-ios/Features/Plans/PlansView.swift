import ComposableArchitecture
import SwiftUI

struct PlansView: View {
    @Bindable var store: StoreOf<PlansFeature>

    var body: some View {
        List {
            ForEach(store.plans, id: \.id) { plan in
                PlanRow(plan: plan)
                    .swipeActions(edge: .trailing) {
                        if store.canManagePlans {
                            Button(role: .destructive) {
                                store.send(.deleteTapped(plan))
                            } label: {
                                Label(String.plan_delete, systemImage: "trash")
                            }
                            Button {
                                store.send(.editTapped(plan))
                            } label: {
                                Label(String.plan_edit, systemImage: "pencil")
                            }
                            .tint(.orange)
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

struct PlansFormView: View {
    @Bindable var store: StoreOf<PlansFormFeature>

    var body: some View {
        NavigationStack {
            Form {
                Section(String.section_main) {
                    TextField(String.plan_title_placeholder, text: $store.title)
                }
                Section {
                    TextField(String.plan_description_placeholder, text: $store.description, axis: .vertical)
                        .lineLimit(4...10)
                }
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
            .navigationTitle(store.existing == nil ? String.plan_add : String.plan_edit)
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

private struct PlanRow: View {
    let plan: Plan

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(plan.title ?? String.plan_untitled).font(.headline)
                Spacer()
                statusBadge
            }
            if let desc = plan.description, !desc.isEmpty {
                Text(desc)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text("\(plan.startDate.formatted(.dateTime.day().month(.abbreviated))) – \(plan.endDate.formatted(.dateTime.day().month(.abbreviated).year()))")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusBadge: some View {
        if plan.isActive {
            Text("● Active").font(.caption.bold()).foregroundStyle(.green)
        } else if plan.isPast {
            Text("✓ Done").font(.caption).foregroundStyle(.secondary)
        } else {
            Text("◌ Upcoming").font(.caption).foregroundStyle(.orange)
        }
    }
}
