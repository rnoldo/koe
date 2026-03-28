import SwiftUI

struct VideoListPanel: View {
    let videos: [Video]
    let currentVideoId: String
    let onSelect: (Video) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Playlist")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.7))
                        .font(.title3)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().background(.white.opacity(0.2))

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
                        Button {
                            onSelect(video)
                        } label: {
                            HStack(spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.5))
                                    .frame(width: 20)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(video.title)
                                        .font(.subheadline)
                                        .foregroundStyle(.white)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    Text(video.formattedDuration)
                                        .font(.caption2)
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                                Spacer()

                                if video.id == currentVideoId {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .foregroundStyle(.yellow)
                                        .font(.caption)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(video.id == currentVideoId
                                ? Color.white.opacity(0.1)
                                : Color.clear)
                        }
                    }
                }
            }
        }
        .frame(width: 260)
        .background(.black.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
