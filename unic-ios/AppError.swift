import SwiftUI

/// Unified error presentation type used across all ViewModels.
/// Wrap any Error or plain message with this type and bind to `.errorAlert()`.
struct AppError: Identifiable {
    /// Unique identifier required by `Identifiable`.
    let id = UUID()
    /// Human-readable error message shown in the alert.
    let message: String

    /// Creates an `AppError` from any `Error`, using its localized description.
    /// - Parameter error: The underlying error to display.
    init(_ error: Error) { message = error.localizedDescription }

    /// Creates an `AppError` from a plain string message.
    /// - Parameter message: The message to display.
    init(_ message: String) { self.message = message }
}

extension View {
    /// Presents a standard error alert bound to an optional `AppError`.
    /// Clears the error on dismissal.
    /// - Parameter error: Binding to an optional `AppError`; set to `nil` to dismiss.
    /// - Returns: A view with the error alert attached.
    func errorAlert(_ error: Binding<AppError?>) -> some View {
        alert(String.error, isPresented: Binding(
            get: { error.wrappedValue != nil },
            set: { if !$0 { error.wrappedValue = nil } }
        )) {
            Button(String.ok, role: .cancel) {}
        } message: {
            Text(error.wrappedValue?.message ?? "")
        }
    }
}
