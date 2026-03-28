import SwiftUI

struct LockScreenView: View {
    let onUnlock: () -> Void

    @Environment(AppStore.self) private var store
    @State private var input = ""
    @State private var shake = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 32) {
                Text("🌙")
                    .font(.system(size: 64))

                Text("Today's watch time is over")
                    .font(.title2)
                    .foregroundStyle(.white)

                // PIN dots
                HStack(spacing: 16) {
                    ForEach(0..<store.settings.pin.count, id: \.self) { i in
                        Circle()
                            .fill(i < input.count ? Color.white : Color.white.opacity(0.3))
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
    }

    private func validatePIN() {
        if input == store.settings.pin {
            onUnlock()
        } else {
            withAnimation(.default) { shake = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                shake = false
                input = ""
            }
        }
    }
}

struct ShakeModifier: ViewModifier {
    var animate: Bool
    func body(content: Content) -> some View {
        content
            .offset(x: animate ? -8 : 0)
            .animation(animate ? .easeInOut(duration: 0.05).repeatCount(5, autoreverses: true) : .default, value: animate)
    }
}
