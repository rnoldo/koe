import SwiftUI

struct BaiduFolderPickerView: View {
    let token: String
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var pathStack: [String] = ["/"]
    @State private var folders: [BaiduFolderItem] = []
    @State private var videoFiles: [BaiduFolderItem] = []
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

                        if !videoFiles.isEmpty {
                            Section("视频文件 (\(videoFiles.count))") {
                                ForEach(videoFiles) { file in
                                    HStack {
                                        Image(systemName: "film")
                                            .foregroundStyle(.blue)
                                        Text(file.name)
                                            .foregroundStyle(.secondary)
                                            .font(.subheadline)
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
        // Brief yield lets the sheet finish its presentation animation before
        // we start the network request, avoiding spurious task cancellations.
        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled else { return }

        isLoading = true
        error = nil
        do {
            let result = try await fetchItems(path: currentPath, token: token)
            folders = result.folders
            videoFiles = result.videos
        } catch is CancellationError {
            return
        } catch let urlError as URLError where urlError.code == .cancelled {
            return
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

private let videoExtensions: Set<String> = ["mp4", "m4v", "mov", "avi", "mkv", "wmv", "flv", "webm", "ts", "rmvb"]

private struct FetchResult {
    let folders: [BaiduFolderItem]
    let videos: [BaiduFolderItem]
}

private func fetchItems(path: String, token: String) async throws -> FetchResult {
    var folders: [BaiduFolderItem] = []
    var videos: [BaiduFolderItem] = []
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
        ]
        let (data, _) = try await HTTPClient.shared.get(c.url!, headers: [:])
        let resp = try JSONDecoder().decode(BaiduListResponse.self, from: data)
        if let errno = resp.errno, errno != 0 {
            throw ScannerError.serverError("Baidu error \(errno): \(resp.errmsg ?? "unknown")")
        }
        guard let list = resp.list else { break }

        for item in list {
            if item.isdir == 1 {
                folders.append(BaiduFolderItem(id: item.path, name: item.displayName, path: item.path))
            } else {
                let ext = (item.path as NSString).pathExtension.lowercased()
                if videoExtensions.contains(ext) {
                    videos.append(BaiduFolderItem(id: item.path, name: item.displayName, path: item.path))
                }
            }
        }
        if list.count < limit { break }
        start += limit
    }
    return FetchResult(folders: folders, videos: videos)
}

struct BaiduFolderItem: Identifiable {
    let id: String
    let name: String
    let path: String
}

private struct BaiduListResponse: Codable {
    let errno: Int?
    let errmsg: String?
    let list: [BaiduListItem]?
}

private struct BaiduListItem: Codable {
    let path: String
    let server_filename: String?
    let isdir: Int?

    var displayName: String {
        server_filename ?? URL(fileURLWithPath: path).lastPathComponent
    }
}
