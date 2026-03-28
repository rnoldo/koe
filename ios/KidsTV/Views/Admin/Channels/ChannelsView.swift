import SwiftUI

struct ChannelsView: View {
    @Environment(AppStore.self) private var store
    @State private var showDeleteConfirm = false
    @State private var deleteTarget: Channel?

    var body: some View {
        List {
            ForEach(store.sortedChannels) { channel in
                NavigationLink(destination: ChannelEditorView(channel: channel)) {
                    ChannelRowView(channel: channel, videoCount: channel.videoIds.count)
                }
            }
            .onDelete { indexSet in
                let sorted = store.sortedChannels
                for i in indexSet {
                    guard i < sorted.count else { continue }
                    deleteTarget = sorted[i]
                }
                showDeleteConfirm = true
            }
            .onMove { from, to in
                store.reorderChannels(from: from, to: to)
            }
        }
        .navigationTitle("Channels")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(destination: ChannelEditorView(channel: nil)) {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .navigationBarLeading) {
                EditButton()
            }
        }
        .alert("Delete Channel", isPresented: $showDeleteConfirm, presenting: deleteTarget) { channel in
            Button("Delete \"\(channel.name)\"", role: .destructive) {
                store.deleteChannel(id: channel.id)
                deleteTarget = nil
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: { channel in
            Text("This will remove the channel and its \(channel.videoIds.count) video references.")
        }
    }
}

struct ChannelRowView: View {
    let channel: Channel
    let videoCount: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: channel.iconName)
                .font(.title3)
                .foregroundStyle(Color(hex: channel.iconColor))
                .frame(width: 36, height: 36)
                .background(Color(hex: channel.iconColor).opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(channel.name).font(.headline)
                Text("\(videoCount) videos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
