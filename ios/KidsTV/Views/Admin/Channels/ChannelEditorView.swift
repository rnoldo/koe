import SwiftUI

private let iconOptions = [
    "tv", "sparkles", "leaf", "atom", "music.note", "book",
    "globe", "star", "heart", "gamecontroller", "film", "camera"
]

private let colorOptions = [
    "#E74C3C", "#E67E22", "#F1C40F", "#2ECC71",
    "#1ABC9C", "#3498DB", "#9B59B6", "#EC407A",
    "#78909C", "#795548"
]

struct ChannelEditorView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    // nil = creating new
    let channel: Channel?

    @State private var name = ""
    @State private var iconName = "tv"
    @State private var iconColor = "#3498DB"
    @State private var defaultVolume: Double = 0.8
    @State private var selectedVideoIds: [String] = []
    @State private var videoSearch = ""
    @State private var sourceFilter: String? = nil

    private var isNew: Bool { channel == nil }

    private var availableVideos: [Video] {
        store.videos.filter { video in
            !selectedVideoIds.contains(video.id) &&
            (videoSearch.isEmpty || video.title.localizedCaseInsensitiveContains(videoSearch)) &&
            (sourceFilter == nil || video.sourceId == sourceFilter)
        }
    }

    private var selectedVideos: [Video] {
        selectedVideoIds.compactMap { store.video(id: $0) }
    }

    var body: some View {
        Form {
            Section("Channel Info") {
                TextField("Channel name", text: $name)

                // Preview
                HStack {
                    Image(systemName: iconName)
                        .font(.title2)
                        .foregroundStyle(Color(hex: iconColor))
                        .frame(width: 44, height: 44)
                        .background(Color(hex: iconColor).opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    Text(name.isEmpty ? "Preview" : name)
                        .font(.headline)
                        .foregroundStyle(name.isEmpty ? .secondary : .primary)
                }
                .padding(.vertical, 4)

                // Icon picker
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(iconOptions, id: \.self) { icon in
                            Button {
                                iconName = icon
                            } label: {
                                Image(systemName: icon)
                                    .frame(width: 36, height: 36)
                                    .background(iconName == icon ? Color.blue.opacity(0.2) : Color.secondary.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(iconName == icon ? Color.blue : Color.clear, lineWidth: 2)
                                    )
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }

                // Color picker
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(colorOptions, id: \.self) { color in
                            Button {
                                iconColor = color
                            } label: {
                                Circle()
                                    .fill(Color(hex: color))
                                    .frame(width: 28, height: 28)
                                    .overlay(
                                        Circle().stroke(Color.white, lineWidth: iconColor == color ? 3 : 0)
                                    )
                                    .shadow(radius: iconColor == color ? 2 : 0)
                            }
                        }
                    }
                }
            }

            Section {
                VStack(alignment: .leading) {
                    Text("Default Volume")
                        .font(.subheadline)
                    HStack {
                        Image(systemName: "speaker.fill")
                            .foregroundStyle(.secondary)
                        Slider(value: $defaultVolume, in: 0...1, step: 0.05)
                        Text("\(Int(defaultVolume * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 40)
                    }
                }
            }

            Section("Videos — Selected (\(selectedVideoIds.count))") {
                if selectedVideos.isEmpty {
                    Text("No videos selected")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                } else {
                    ForEach(selectedVideos) { video in
                        Button {
                            selectedVideoIds.removeAll { $0 == video.id }
                        } label: {
                            HStack {
                                Text(video.title).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                            }
                        }
                    }
                    .onMove { from, to in
                        selectedVideoIds.move(fromOffsets: from, toOffset: to)
                    }
                }
            }

            Section {
                // Source filter
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        filterChip("All", nil)
                        ForEach(store.sources) { s in filterChip(s.name, s.id) }
                    }
                }
                TextField("Search videos", text: $videoSearch)
            } header: {
                Text("Add Videos")
            }

            Section {
                ForEach(availableVideos) { video in
                    Button {
                        selectedVideoIds.append(video.id)
                    } label: {
                        HStack {
                            Text(video.title).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "plus.circle.fill").foregroundStyle(.green)
                        }
                    }
                }
            }
        }
        .navigationTitle(isNew ? "New Channel" : "Edit Channel")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(name.isEmpty)
            }
            if !isNew {
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                }
            }
        }
        .onAppear { loadFromChannel() }
    }

    private func filterChip(_ label: String, _ id: String?) -> some View {
        Button { sourceFilter = id } label: {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(sourceFilter == id ? Color.blue : Color.secondary.opacity(0.15))
                .foregroundStyle(sourceFilter == id ? .white : .primary)
                .clipShape(Capsule())
        }
    }

    private func loadFromChannel() {
        guard let ch = channel else { return }
        name = ch.name
        iconName = ch.iconName
        iconColor = ch.iconColor
        defaultVolume = ch.defaultVolume
        selectedVideoIds = ch.videoIds
    }

    private func save() {
        if isNew {
            store.addChannel(Channel(
                name: name, iconName: iconName, iconColor: iconColor,
                defaultVolume: defaultVolume, videoIds: selectedVideoIds
            ))
        } else if let ch = channel {
            var updated = ch
            updated.name = name
            updated.iconName = iconName
            updated.iconColor = iconColor
            updated.defaultVolume = defaultVolume
            updated.videoIds = selectedVideoIds
            store.updateChannel(updated)
        }
        dismiss()
    }
}
