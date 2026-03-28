import SwiftUI

struct SourceDetailView: View {
    @Environment(AppStore.self) private var store
    let source: MediaSource

    private var liveSource: MediaSource? { store.sources.first { $0.id == source.id } }
    private var sourceVideos: [Video] { store.videos(for: source.id) }

    var body: some View {
        List {
            if let src = liveSource {
                Section("Status") {
                    LabeledContent("Status") {
                        HStack {
                            Circle().fill(statusColor(src)).frame(width: 8, height: 8)
                            Text(src.scanStatus.rawValue.capitalized)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let date = src.lastScanDate {
                        LabeledContent("Last Scan", value: date.formatted(.relative(presentation: .named)))
                    }
                    LabeledContent("Videos", value: "\(src.videoCount)")

                    if let error = src.errorMessage {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }

                    Button {
                        Task { await store.scanSource(id: src.id) }
                    } label: {
                        Label("Rescan", systemImage: "arrow.clockwise")
                    }
                    .disabled(src.scanStatus == .scanning)
                }

                Section("Enable") {
                    Toggle("Enabled", isOn: Binding(
                        get: { src.isEnabled },
                        set: { v in
                            var updated = src
                            updated.isEnabled = v
                            store.updateSource(updated)
                        }
                    ))
                }
            }

            Section("Videos (\(sourceVideos.count))") {
                ForEach(sourceVideos) { video in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(video.title).font(.subheadline)
                        HStack {
                            if let res = video.resolution {
                                Text(res).font(.caption).foregroundStyle(.secondary)
                            }
                            if let size = video.formattedFileSize {
                                Text("·").foregroundStyle(.secondary)
                                Text(size).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(video.formattedDuration).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle(source.name)
    }

    private func statusColor(_ src: MediaSource) -> Color {
        switch src.scanStatus {
        case .idle: return src.isEnabled ? .green : .gray
        case .scanning: return .yellow
        case .error: return .red
        }
    }
}
