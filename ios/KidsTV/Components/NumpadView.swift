import SwiftUI

struct NumpadView: View {
    @Binding var input: String
    var maxLength: Int = 4
    var onSubmit: () -> Void

    private let keys: [[String]] = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["", "0", "⌫"]
    ]

    var body: some View {
        VStack(spacing: 12) {
            ForEach(keys, id: \.self) { row in
                HStack(spacing: 12) {
                    ForEach(row, id: \.self) { key in
                        if key.isEmpty {
                            Color.clear.frame(width: 72, height: 56)
                        } else {
                            Button {
                                handleKey(key)
                            } label: {
                                Text(key)
                                    .font(.title2.bold())
                                    .frame(width: 72, height: 56)
                                    .background(Color.secondary.opacity(0.15))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
            }
        }
    }

    private func handleKey(_ key: String) {
        if key == "⌫" {
            if !input.isEmpty { input.removeLast() }
        } else {
            guard input.count < maxLength else { return }
            input.append(key)
            if input.count == maxLength { onSubmit() }
        }
    }
}
