import SwiftUI

struct FetchScreen: View {
    var body: some View {
        VStack(spacing: 20) {
            Image("AppIcon")
                .resizable()
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            ProgressView()
                .scaleEffect(1.2)
        }
    }
}
