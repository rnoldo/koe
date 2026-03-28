import SwiftUI

struct AdminRootView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        if store.isAdminAuthenticated {
            adminTabView
        } else {
            PINEntryView()
        }
    }

    private var adminTabView: some View {
        TabView {
            NavigationStack {
                SourcesView()
            }
            .tabItem { Label("Sources", systemImage: "server.rack") }

            NavigationStack {
                LibraryView()
            }
            .tabItem { Label("Library", systemImage: "film.stack") }

            NavigationStack {
                ChannelsView()
            }
            .tabItem { Label("Channels", systemImage: "tv") }

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gear") }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Logout") { store.logoutAdmin() }
            }
        }
    }
}
