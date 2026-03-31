import SwiftUI

struct BaiduFolderPickerView: View {
    let token: String
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var pathStack: [String] = ["/"]
    @State private var folders: [BaiduFolderItem] = []
    @State private var isLoading = false
    @State private var error: String?

    private var currentPath: String { pathStack.last ?? "/" }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.yellow)
                        Text(error)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                        Button("Retry") { Task { await loadFolders() } }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section {
                            Button {
                                onSelect(currentPath)
                                dismiss()
                            } label: {
                                Label("选择此文件夹", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .bold()
                            }
                        }

                        Section("子文件夹") {
                            if folders.isEmpty {
                                Text("没有子文件夹")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(folders) { folder in
                                    Button {
                                        pathStack.append(folder.path)
                                    } label: {
                                        HStack {
                                            Image(systemName: "folder.fill")
                                                .foregroundStyle(.yellow)
                                            Text(folder.name)
                                                .foregroundStyle(.primary)
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(currentPath == "/" ? "根目录" : URL(fileURLWithPath: currentPath).lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                if pathStack.count > 1 {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: { pathStack.removeLast() }) {
                            Image(systemName: "chevron.left")
                            Text("返回")
                        }
                    }
                }
            }
        }
        .task(id: currentPath) { await loadFolders() }
    }

    private func loadFolders() async {
        isLoading = true
        error = nil
        do {
            folders = try await fetchFolders(path: currentPath, token: token)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

private func fetchFolders(path: String, token: String) async throws -> [BaiduFolderItem] {
    var all: [BaiduFolderItem] = []
    var start = 0
    let limit = 100

    while true {
        var c = URLComponents(string: "https://pan.baidu.com/rest/2.0/xpan/file")!
        c.queryItems = [
            URLQueryItem(name: "method", value: "list"),
            URLQueryItem(name: "access_token", value: token),
            URLQueryItem(name: "dir", value: path),
            URLQueryItem(name: "start", value: "\(start)"),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "order", value: "name"),
            URLQueryItem(name: "folder", value: "1"),   // folders only
        ]
        let (data, _) = try await HTTPClient.shared.get(c.url!, headers: [:])
        let resp = try JSONDecoder().decode(BaiduListResponse.self, from: data)
        guard let list = resp.list else { break }

        for item in list where item.isdir == 1 {
            all.append(BaiduFolderItem(
                id: "\(item.fs_id)",
                name: item.server_filename,
                path: item.path
            ))
        }
        if list.count < limit { break }
        start += limit
    }
    return all
}

struct BaiduFolderItem: Identifiable {
    let id: String
    let name: String
    let path: String
}

private struct BaiduListResponse: Codable {
    let list: [BaiduListItem]?
}

private struct BaiduListItem: Codable {
    let fs_id: Int64
    let path: String
    let server_filename: String
    let isdir: Int
}
