import SwiftUI

/// Unified error presentation type used across all ViewModels.
/// Wrap any Error or plain message with this type and bind to `.errorAlert()`.
struct AppError: Identifiable {
    let id = UUID()
    let message: String

    init(_ error: Error) { message = error.localizedDescription }
    init(_ message: String) { self.message = message }
}

extension View {
    /// Presents a standard error alert bound to an optional `AppError`.
    /// Clears the error on dismissal.
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
