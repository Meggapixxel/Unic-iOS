import SwiftUI

// MARK: - Not Logged In

struct NotLoggedInView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "lock.shield")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            VStack(spacing: 8) {
                Text(String.auth_no_access_title)
                    .font(.title2.bold())
                Text(String.auth_no_access_body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            Spacer()
        }
    }
}

// MARK: - Login

struct AuthScreen: View {
    @ObservedObject private var auth = AuthService.shared
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var focused: AuthField?

    var body: some View {
        ZStack {
            backgroundGradient
            VStack(spacing: 0) {
                Spacer()
                headerSection
                    .padding(.bottom, 40)
                loginCard
                Spacer()
                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .ignoresSafeArea()
        .onAppear { focused = .email }
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color.accentColor.opacity(0.85),
                Color.accentColor.opacity(0.4),
                Color(.systemGroupedBackground)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image("AppIcon")
                .resizable()
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
            Text(String.auth_login_title)
                .font(.title.bold())
                .foregroundStyle(.white)
        }
    }

    // MARK: - Login Card

    private var loginCard: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                TextField(String.auth_email_placeholder, text: $email)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.next)
                    .onSubmit { focused = .password }
                    .focused($focused, equals: .email)
                    .authFieldStyle()

                SecureField(String.auth_password_placeholder, text: $password)
                    .submitLabel(.go)
                    .onSubmit { login() }
                    .focused($focused, equals: .password)
                    .authFieldStyle()
            }

            if let err = errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(action: login) {
                Group {
                    if isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text(String.auth_login_button)
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .disabled(email.isEmpty || password.isEmpty || isLoading)
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
    }

    // MARK: - Action

    private func login() {
        guard !email.isEmpty, !password.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        Task {
            defer { isLoading = false }
            do {
                try await auth.login(email: email, password: password)
            } catch {
                errorMessage = error.localizedDescription
                password = ""
            }
        }
    }
}

// MARK: - Helpers

private enum AuthField { case email, password }

private extension View {
    func authFieldStyle() -> some View {
        self
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}
