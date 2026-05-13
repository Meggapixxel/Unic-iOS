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
            AppView(store: Store(initialState: .loading) { AppFeature() })
        }
    }
}
