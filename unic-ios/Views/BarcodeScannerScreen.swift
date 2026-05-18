import SwiftUI

/// Full-screen overlay that hosts `BarcodeScannerView` with a dismiss button and a hint label.
struct BarcodeScannerScreen: View {
    /// Called with the scanned barcode string once a code is successfully read.
    let onScan: (String) -> Void
    /// Called when the user taps the close button.
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            BarcodeScannerView(onScan: onScan)
                .ignoresSafeArea()

            VStack {
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.black.opacity(0.4), in: Circle())
                    }
                    .padding(.trailing, 20)
                    .padding(.top, 16)
                }

                Spacer()

                Text(String.barcode_hint)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding(.bottom, 60)
            }
        }
    }
}
