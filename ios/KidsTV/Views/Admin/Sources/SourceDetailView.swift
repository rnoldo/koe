import SwiftUI

struct SourceDetailView: View {
    @Environment(AppStore.self) private var store
    let source: MediaSource

    @State private var isReauthing = false
    @State private var reauthError: String?
    @State private var showFolderPicker = false

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

                if src.type == .baiduPan || src.type == .aliyunDrive {
                    Section("Account") {
                        if let error = reauthError {
                            Text(error).foregroundStyle(.red).font(.caption)
                        }
                        Button {
                            reauthError = nil
                            Task { await reAuthenticate(source: src) }
                        } label: {
                            if isReauthing {
                                HStack {
                                    ProgressView().scaleEffect(0.8)
                                    Text("Signing in…")
                                }
                            } else {
                                Label(
                                    src.config.accessToken != nil ? "Switch Account" : "Sign In",
                                    systemImage: "person.badge.key"
                                )
                            }
                        }
                        .disabled(isReauthing)
                    }
                }

                if src.type == .baiduPan, src.config.accessToken != nil {
                    Section("Scan Folder") {
                        LabeledContent("Current Folder") {
                            Text(src.config.rootFolderId ?? "/")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Button {
                            showFolderPicker = true
                        } label: {
                            Label("Choose Folder…", systemImage: "folder.badge.gear")
                        }
                    }
                    .sheet(isPresented: $showFolderPicker) {
                        BaiduFolderPickerView(token: src.config.accessToken!) { selectedPath in
                            var updated = src
                            updated.config.rootFolderId = selectedPath
                            store.updateSource(updated)
                        }
                    }
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

    @MainActor
    private func reAuthenticate(source: MediaSource) async {
        isReauthing = true
        defer { isReauthing = false }
        do {
            let tokens: OAuthTokens
            switch source.type {
            case .baiduPan:
                let code = try await OAuthManager.shared.authenticate(
                    authURL: BaiduPanScanner.authURL,
                    callbackScheme: BaiduPanScanner.callbackScheme,
                    ephemeral: true
                )
                tokens = try await OAuthManager.shared.exchangeToken(
                    tokenURL: BaiduPanScanner.tokenURL,
                    code: code,
                    clientId: BaiduPanScanner.clientId,
                    clientSecret: BaiduPanScanner.clientSecret,
                    redirectURI: BaiduPanScanner.redirectURI
                )
            case .aliyunDrive:
                let code = try await OAuthManager.shared.authenticate(
                    authURL: AliyunDriveScanner.authURL,
                    callbackScheme: AliyunDriveScanner.callbackScheme,
                    ephemeral: true
                )
                tokens = try await OAuthManager.shared.exchangeToken(
                    tokenURL: AliyunDriveScanner.tokenURL,
                    code: code,
                    clientId: AliyunDriveScanner.clientId,
                    clientSecret: nil,
                    redirectURI: AliyunDriveScanner.redirectURI
                )
            default:
                return
            }
            var updated = source
            updated.config.accessToken = tokens.accessToken
            updated.config.refreshToken = tokens.refreshToken
            if let exp = tokens.expiresIn {
                updated.config.tokenExpiry = Date().addingTimeInterval(TimeInterval(exp))
            }
            store.updateSource(updated)
        } catch {
            reauthError = error.localizedDescription
        }
    }

    private func statusColor(_ src: MediaSource) -> Color {
        switch src.scanStatus {
        case .idle: return src.isEnabled ? .green : .gray
        case .scanning: return .yellow
        case .error: return .red
        }
    }
}
