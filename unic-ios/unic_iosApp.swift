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
        Task {
            _ = await NotificationService.shared.requestPermission()
        }
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

// MARK: - Root View

struct RootView: View {
    @ObservedObject private var auth = AuthService.shared
    @State private var showGreeting = false

    var body: some View {
        ZStack(alignment: .bottom) {
            if auth.isLoggedIn {
                TabView {
                    SalonListView()
                        .tabItem { Label("CRM", systemImage: "person.2") }
                    FlexiBeeView()
                        .tabItem { Label("FlexiBee", systemImage: "chart.bar.doc.horizontal") }
                }
                .onAppear {
                    withAnimation(.easeIn(duration: 0.3)) { showGreeting = true }
                    Task {
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                        withAnimation(.easeOut(duration: 0.4)) { showGreeting = false }
                    }
                }
            } else {
                LoginView()
            }

            if showGreeting, let user = auth.currentUser {
                Text("Привіт, \(user.firstName)!")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.thinMaterial)
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                    .padding(.bottom, 90)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}
