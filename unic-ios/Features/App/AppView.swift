import ComposableArchitecture
import SwiftUI

struct AppView: View {
    @Bindable var store: StoreOf<AppFeature>

    var body: some View {
        Group {
            switch store.state {
            case .loading:
                ProgressView()

            case .auth:
                if let authStore = store.scope(state: \.auth, action: \.auth) {
                    AuthView(store: authStore)
                }

            case .welcome:
                if let welcomeStore = store.scope(state: \.welcome, action: \.welcome) {
                    WelcomeView(store: welcomeStore)
                }

            case .main:
                if let mainStore = store.scope(state: \.main, action: \.main) {
                    MainView(store: mainStore)
                }
            }
        }
        .task { store.send(.onAppear) }
    }
}

// MARK: - Location Gate View

struct LocationGateView: View {
    let onAuthorized: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "location.slash.fill")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            VStack(spacing: 8) {
                Text(String(localized: "location_required_title"))
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(String(localized: "location_required_description"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label(String(localized: "open_settings"), systemImage: "gear")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 32)
            Spacer()
        }
    }
}
