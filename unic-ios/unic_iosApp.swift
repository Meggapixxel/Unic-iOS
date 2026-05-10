//
//  unic_iosApp.swift
//  unic-ios
//
//  Created by Vadym Zhydenko on 04/02/2026.
//

import SwiftUI
import FirebaseCore
import UserNotifications

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
    case main
}

// MARK: - Root View

struct RootView: View {
    @ObservedObject private var auth = AuthService.shared
    @State private var appState: AppState = .auth

    var body: some View {
        Group {
            switch appState {
            case .auth:
                AuthScreen()
            case .fetch:
                FetchScreen()
            case .main:
                MainScreen()
            }
        }
        .task(id: auth.isLoggedIn) { await handleAuthChange(auth.isLoggedIn) }
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
        appState = .main
    }
}
