//
//  unic_iosApp.swift
//  unic-ios
//
//  Created by Vadym Zhydenko on 04/02/2026.
//

import SwiftUI
import FirebaseCore
import UserNotifications
import CoreLocation

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()
        Task { _ = await NotificationService.shared.requestPermission() }
        return true
    }
}

@main
struct unic_iosApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

// MARK: - App State

private enum AppState {
    case auth
    case fetch
    case locationGate
    case main
}

// MARK: - Root View

struct RootView: View {
    @ObservedObject private var auth = AuthService.shared
    @ObservedObject private var locationManager = LocationManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var appState: AppState = .auth

    var body: some View {
        Group {
            switch appState {
            case .auth:
                AuthScreen()
            case .fetch:
                FetchScreen()
            case .locationGate:
                LocationGateScreen()
            case .main:
                MainScreen()
            }
        }
        .task(id: auth.isLoggedIn) { await handleAuthChange(auth.isLoggedIn) }
        .onChange(of: locationManager.authStatus) { _, status in
            guard appState == .locationGate else { return }
            if locationManager.isAuthorized { appState = .main }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, appState == .locationGate else { return }
            if locationManager.isAuthorized { appState = .main }
        }
    }
}

// MARK: - State transitions

extension RootView {
    private func handleAuthChange(_ loggedIn: Bool) async {
        if loggedIn {
            appState = .fetch
            await loadConfig()
        } else {
            appState = .auth
        }
    }

    private func loadConfig() async {
        await withTaskGroup { group in
            group.addTask {
                await FirebaseService.shared.loadBundleCodes()
            }
            group.addTask {
                await FirebaseService.shared.loadTestDriveConfig()
            }
        }
        if auth.isSales && !locationManager.isAuthorized {
            LocationManager.shared.requestPermission()
            appState = .locationGate
        } else {
            appState = .main
        }
    }
}

// MARK: - Location Gate View

private struct LocationGateScreen: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "location.slash.fill")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            VStack(spacing: 8) {
                Text("location_required_title")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text("location_required_description")
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
                Label("open_settings", systemImage: "gear")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 32)
            Spacer()
        }
    }
}
