import ComposableArchitecture
import SwiftUI

/// Full-screen splash shown while the app preloads data after a successful login.
struct WelcomeView: View {
    let store: StoreOf<WelcomeFeature>

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 16) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 56, weight: .light))
                        .foregroundStyle(Color.accentColor)

                    VStack(spacing: 6) {
                        Text("UNIC")
                            .font(.largeTitle.weight(.bold))
                        Text("Привіт, \(store.user.firstName)!")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                ProgressView()
                    .scaleEffect(1.2)
                    .padding(.bottom, 48)
            }
        }
        .onAppear {
            store.send(.onAppear)
            LocationManager.shared.requestPermission()
        }
    }
}
