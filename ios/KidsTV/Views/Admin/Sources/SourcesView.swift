import SwiftUI

struct SourcesView: View {
    @Environment(AppStore.self) private var store
    @State private var showAddSheet = false
    @State private var showDeleteConfirm = false
    @State private var deleteTarget: MediaSource?
    @State private var isEditing = false

    var body: some View {
        List {
            ForEach(store.sources) { source in
                NavigationLink(destination: SourceDetailView(source: source)) {
                    SourceRowView(source: source)
                }
            }
            .onDelete { indexSet in
                for i in indexSet {
                    guard i < store.sources.count else { continue }
                    deleteTarget = store.sources[i]
                }
                showDeleteConfirm = true
            }
        }
        .navigationTitle("Sources")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                EditButton()
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddSourceView()
        }
        .alert("Delete Source", isPresented: $showDeleteConfirm, presenting: deleteTarget) { source in
            Button("Delete \"\(source.name)\"", role: .destructive) {
                store.deleteSource(id: source.id)
                deleteTarget = nil
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: { source in
            Text("This will also remove all \(source.videoCount) videos from this source.")
        }
    }
}

struct SourceRowView: View {
    @Environment(AppStore.self) private var store
    let source: MediaSource

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(source.name).font(.headline)
                Text(source.type.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(source.videoCount) videos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if source.scanStatus == .scanning {
                    ProgressView().scaleEffect(0.7)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch source.scanStatus {
        case .idle: return source.isEnabled ? .green : .gray
        case .scanning: return .yellow
        case .error: return .red
        }
    }
}
