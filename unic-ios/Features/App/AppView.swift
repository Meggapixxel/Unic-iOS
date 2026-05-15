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

