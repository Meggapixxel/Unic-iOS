import ComposableArchitecture
import CoreLocation
import SwiftUI

struct WelcomeView: View {
    let store: StoreOf<WelcomeFeature>
    @ObservedObject private var locationManager = LocationManager.shared

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
        .onReceive(locationManager.$authStatus) { status in
            guard status != .notDetermined else { return }
            store.send(.locationChecked)
        }
        .onAppear {
            if locationManager.authStatus != .notDetermined {
                store.send(.locationChecked)
            }
        }
    }
}
