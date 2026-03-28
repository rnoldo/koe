import SwiftUI

struct PINEntryView: View {
    @Environment(AppStore.self) private var store
    @State private var input = ""
    @State private var shake = false

    var body: some View {
        VStack(spacing: 40) {
            VStack(spacing: 8) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
                Text("Parent Access")
                    .font(.title2.bold())
                Text("Enter your PIN to continue")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // PIN dots
            HStack(spacing: 16) {
                ForEach(0..<store.settings.pin.count, id: \.self) { i in
                    Circle()
                        .fill(i < input.count ? Color.primary : Color.secondary.opacity(0.3))
                        .frame(width: 14, height: 14)
                }
            }
            .modifier(ShakeModifier(animate: shake))

            NumpadView(input: $input, maxLength: store.settings.pin.count) {
                validatePIN()
            }
        }
        .padding(40)
    }

    private func validatePIN() {
        if store.authenticateAdmin(pin: input) {
            input = ""
        } else {
            withAnimation { shake = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                shake = false
                input = ""
            }
        }
    }
}
