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

struct LoginView: View {
    @ObservedObject private var auth = AuthService.shared
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var focused: Field?

    private enum Field { case email, password }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "person.badge.key.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)
                .padding(.bottom, 32)

            Text(String.auth_login_title)
                .font(.title2.bold())
                .padding(.bottom, 28)

            VStack(spacing: 12) {
                TextField(String.auth_email_placeholder, text: $email)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($focused, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focused = .password }

                SecureField(String.auth_password_placeholder, text: $password)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { login() }
            }
            .padding(.horizontal, 32)

            if let err = errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.top, 8)
                    .padding(.horizontal, 32)
                    .multilineTextAlignment(.center)
            }

            Button(action: login) {
                Group {
                    if isLoading {
                        ProgressView()
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
            .padding(.horizontal, 32)
            .padding(.top, 20)

            Spacer()
        }
        .onAppear { focused = .email }
    }

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
