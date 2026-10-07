import SwiftUI

@main
struct GRTransferApp: App {
    @StateObject private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store)
                .tint(Color.accentColor)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { store.enteredBackground() }
                    if phase == .active { store.enteredForeground() }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @State private var tab = 0
    @Environment(\.horizontalSizeClass) private var windowSizeClass
    var body: some View {
        TabView(selection: $tab) {
            TransferView(openSettings: { tab = 1 })
                .environment(\.horizontalSizeClass, windowSizeClass)
                .tabItem { Label("传输", systemImage: "arrow.down.circle") }.tag(0)
            SettingsView()
                .environment(\.horizontalSizeClass, windowSizeClass)
                .tabItem { Label("设置", systemImage: "gearshape") }.tag(1)
        }
        // The brief calls for a bottom tab bar on iPad too. A compact environment keeps
        // the system's tab bar at the bottom; content grids still size from available width.
        .environment(\.horizontalSizeClass, .compact)
        .alert("请检查连接或权限", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("知道了", role: .cancel) { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }
}
