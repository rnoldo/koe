import SwiftUI

struct LibraryView: View {
    @Environment(AppStore.self) private var store
    @State private var search = ""
    @State private var sourceFilter: String? = nil
    @State private var isGrid = true

    private var filtered: [Video] {
        store.videos.filter { video in
            let matchesSearch = search.isEmpty || video.title.localizedCaseInsensitiveContains(search)
            let matchesSource = sourceFilter == nil || video.sourceId == sourceFilter
            return matchesSearch && matchesSource
        }
    }

    private func channelBadges(for video: Video) -> [Channel] {
        store.channels.filter { $0.videoIds.contains(video.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip(label: "All", id: nil)
                    ForEach(store.sources) { source in
                        filterChip(label: source.name, id: source.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            Divider()

            if isGrid {
                gridView
            } else {
                listView
            }
        }
        .navigationTitle("Library")
        .searchable(text: $search, prompt: "Search videos")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation { isGrid.toggle() }
                } label: {
                    Image(systemName: isGrid ? "list.bullet" : "square.grid.2x2")
                }
            }
        }
    }

    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                ForEach(filtered) { video in
                    VideoGridCard(video: video, channels: channelBadges(for: video))
                }
            }
            .padding(16)
        }
    }

    private var listView: some View {
        List(filtered) { video in
            VideoListRow(video: video, channels: channelBadges(for: video))
        }
    }

    private func filterChip(label: String, id: String?) -> some View {
        Button {
            sourceFilter = id
        } label: {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(sourceFilter == id ? Color.blue : Color.secondary.opacity(0.15))
                .foregroundStyle(sourceFilter == id ? .white : .primary)
                .clipShape(Capsule())
        }
    }
}

struct VideoGridCard: View {
    let video: Video
    let channels: [Channel]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hex: video.thumbnailColor))
                .aspectRatio(16/9, contentMode: .fit)
                .overlay(alignment: .bottomTrailing) {
                    Text(video.formattedDuration)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.7))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(6)
                }

            Text(video.title)
                .font(.caption.bold())
                .lineLimit(2)

            if !channels.isEmpty {
                HStack(spacing: 4) {
                    ForEach(channels.prefix(3)) { ch in
                        Text(ch.name)
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color(hex: ch.iconColor).opacity(0.2))
                            .foregroundStyle(Color(hex: ch.iconColor))
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }
}

struct VideoListRow: View {
    let video: Video
    let channels: [Channel]

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(hex: video.thumbnailColor))
                .frame(width: 80, height: 45)

            VStack(alignment: .leading, spacing: 3) {
                Text(video.title).font(.subheadline).lineLimit(1)
                HStack(spacing: 6) {
                    if let res = video.resolution {
                        Text(res).font(.caption2).foregroundStyle(.secondary)
                    }
                    if let size = video.formattedFileSize {
                        Text(size).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(video.formattedDuration).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
