//
//  unic_iosApp.swift
//  unic-ios
//
//  Created by Vadym Zhydenko on 04/02/2026.
//

import ComposableArchitecture
import FirebaseCore
import SwiftUI
import UserNotifications

/// UIKit application delegate responsible for bootstrapping Firebase and requesting notification permissions.
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()
        Task { _ = await NotificationService.shared.requestPermission() }
        return true
    }
}

/// Application entry point; wires `AppDelegate` and creates the root TCA store.
@main
struct unic_iosApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            AppView(store: Store(initialState: .loading) { AppFeature() })
        }
    }
}
