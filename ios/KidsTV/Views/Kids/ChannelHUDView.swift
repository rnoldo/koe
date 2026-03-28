import SwiftUI

struct ChannelHUDView: View {
    let channel: Channel
    let channelIndex: Int
    let totalChannels: Int
    let videoTitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: channel.iconName)
                    .foregroundStyle(Color(hex: channel.iconColor))
                Text(channel.name)
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text("CH \(channelIndex + 1) / \(totalChannels)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            Text(videoTitle)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 24)
    }
}
