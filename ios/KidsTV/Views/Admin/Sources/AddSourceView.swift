import SwiftUI

struct AddSourceView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var type: SourceType = .local
    @State private var config = SourceConfig()
    @State private var showPassword = false
    @State private var showFolderPicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section("General") {
                    TextField("Name", text: $name)
                    Picker("Type", selection: $type) {
                        ForEach(SourceType.allCases, id: \.self) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                }

                Section("Configuration") {
                    configFields
                }
            }
            .navigationTitle("Add Source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addSource() }
                        .disabled(name.isEmpty)
                }
            }
            .fileImporter(
                isPresented: $showFolderPicker,
                allowedContentTypes: [.folder]
            ) { result in
                if case .success(let url) = result {
                    config.dirPath = url.path
                    // Save bookmark so we can re-access after restart
                    config.dirBookmark = try? url.bookmarkData(
                        options: .minimalBookmark,
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                    if name.isEmpty {
                        name = url.lastPathComponent
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var configFields: some View {
        switch type {
        case .local:
            Button {
                showFolderPicker = true
            } label: {
                HStack {
                    Image(systemName: "folder")
                    if let path = config.dirPath {
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                            .foregroundStyle(.primary)
                    } else {
                        Text("Choose Folder…")
                            .foregroundStyle(.blue)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)

            // Direct path input — useful in the iOS Simulator where Mac paths are accessible
            TextField("Or type a path, e.g. /Users/you/Videos", text: Binding(
                get: { config.dirPath ?? "" },
                set: { config.dirPath = $0.isEmpty ? nil : $0; config.dirBookmark = nil }
            ))
            .font(.caption)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)

        case .webdav:
            TextField("URL", text: urlBinding)
            TextField("Username", text: usernameBinding)
            passwordField
        case .smb:
            TextField("Host", text: Binding(get: { config.host ?? "" }, set: { config.host = $0 }))
            TextField("Share", text: Binding(get: { config.share ?? "" }, set: { config.share = $0 }))
            TextField("Username", text: usernameBinding)
            passwordField
        case .emby, .jellyfin:
            TextField("Server URL", text: serverUrlBinding)
            TextField("API Key", text: Binding(get: { config.apiKey ?? "" }, set: { config.apiKey = $0 }))
            TextField("User ID", text: Binding(get: { config.userId ?? "" }, set: { config.userId = $0 }))
        case .aliyunDrive, .baiduPan, .pan115:
            TextField("Root Folder ID (optional)", text: Binding(
                get: { config.rootFolderId ?? "" },
                set: { config.rootFolderId = $0.isEmpty ? nil : $0 }
            ))
        }
    }

    private var passwordField: some View {
        HStack {
            if showPassword {
                TextField("Password", text: passwordBinding)
            } else {
                SecureField("Password", text: passwordBinding)
            }
            Button { showPassword.toggle() } label: {
                Image(systemName: showPassword ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var urlBinding: Binding<String> {
        Binding(get: { config.url ?? "" }, set: { config.url = $0 })
    }
    private var usernameBinding: Binding<String> {
        Binding(get: { config.username ?? "" }, set: { config.username = $0 })
    }
    private var passwordBinding: Binding<String> {
        Binding(get: { config.password ?? "" }, set: { config.password = $0 })
    }
    private var serverUrlBinding: Binding<String> {
        Binding(get: { config.serverUrl ?? "" }, set: { config.serverUrl = $0 })
    }

    private func addSource() {
        let source = MediaSource(name: name, type: type, config: config)
        store.addSource(source)
        dismiss()
    }
}
