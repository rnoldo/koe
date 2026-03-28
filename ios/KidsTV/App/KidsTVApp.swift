import SwiftUI

@main
struct KidsTVApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
    }
}

struct ContentView: View {
    @Environment(AppStore.self) private var store
    @State private var tab: Tab = .kids

    enum Tab { case kids, admin }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            switch tab {
            case .kids:
                KidsView()
                    .ignoresSafeArea()
            case .admin:
                AdminRootView()
            }

            // Floating switch button (kids → admin requires PIN on admin side)
            Button {
                withAnimation { tab = tab == .kids ? .admin : .kids }
                if tab == .kids { store.logoutAdmin() }
            } label: {
                Image(systemName: tab == .kids ? "gearshape" : "tv")
                    .padding(10)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .padding(.top, 50)
            .padding(.trailing, 16)
        }
        .preferredColorScheme(tab == .kids ? .dark : nil)
    }
}
