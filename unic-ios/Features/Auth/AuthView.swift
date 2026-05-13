import ComposableArchitecture
import SwiftUI

struct AuthView: View {
    @Bindable var store: StoreOf<AuthFeature>

    var body: some View {
        VStack(spacing: 24) {
            Text(String.auth_login_title)
                .font(.largeTitle.bold())

            VStack(spacing: 16) {
                TextField(String.auth_email_placeholder, text: $store.email)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)

                SecureField(String.auth_password_placeholder, text: $store.password)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal)

            if let error = store.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button(String.auth_login_button) {
                store.send(.loginTapped)
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.isLoading)

            if store.isLoading { ProgressView() }
        }
        .padding()
    }
}
