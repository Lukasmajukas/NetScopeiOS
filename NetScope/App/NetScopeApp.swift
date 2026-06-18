// NetScope for iPhone — SwiftUI.
//
// This is NOT a port of the macOS NetScope (iOS forbids the LAN scanning,
// shell tools and embedded web server the Mac app is built on). It implements
// the parts iOS actually allows:
//   • Internet speed test (full) — gauge, ISP/server, saved history, CSV export
//   • Device finder via Bonjour/mDNS (services only — iOS hides MACs & blocks
//     full ARP/ping sweeps)
//   • Your connection (Wi-Fi/Cellular, local IP, SSID if entitled)
//   • Learn — Wi-Fi band/width/speed explainers
//
// Open in Xcode 15+/iOS 16, set your signing Team under Signing & Capabilities,
// pick your iPhone, and Run. Builds clean against the iOS 27 SDK.

import SwiftUI

@main
struct NetScopeApp: App {
    @State private var history = HistoryStore()
    @State private var connection = ConnectionMonitor()
    @State private var location = LocationProvider()
    @State private var pro = ProManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(history)
                .environment(connection)
                .environment(location)
                .environment(pro)
                .preferredColorScheme(.dark)
                .tint(.nsAccent)
        }
    }
}

struct ContentView: View {
    @Environment(ConnectionMonitor.self) private var conn
    // Initial tab can be set via the "startTab" launch argument/default; 0 normally.
    @State private var tab = ContentView.clampedStartTab()

    private static func clampedStartTab() -> Int {
        let raw = UserDefaults.standard.integer(forKey: "startTab")
        return (0...4).contains(raw) ? raw : 0
    }

    // Tags currently on screen (Devices/tag 1 is hidden on cellular). Tools is tag 4.
    private var presentTags: [Int] { conn.isCellular ? [0, 2, 4, 3] : [0, 1, 2, 4, 3] }

    // A selection that always resolves to a tab that is actually present, so a
    // hidden or out-of-range tag can never leave the TabView blank. The stored
    // `tab` is kept, so the Devices tab reappears when you return to Wi-Fi.
    private var selection: Binding<Int> {
        Binding(get: { presentTags.contains(tab) ? tab : 0 },
                set: { tab = $0 })
    }

    var body: some View {
        TabView(selection: selection) {
            SpeedTestView()
                .tabItem { Label("Speed", systemImage: "speedometer") }
                .tag(0)
            // The Bonjour device finder only makes sense on a local network —
            // hide it on cellular, where there's nothing local to browse.
            if !conn.isCellular {
                DevicesView()
                    .tabItem { Label("Devices", systemImage: "dot.radiowaves.left.and.right") }
                    .tag(1)
            }
            ConnectionView()
                .tabItem {
                    Label("Connection",
                          systemImage: conn.isCellular
                          ? "antenna.radiowaves.left.and.right" : "wifi")
                }
                .tag(2)
            ToolsView()
                .tabItem { Label("Tools", systemImage: "wrench.and.screwdriver") }
                .tag(4)
            LearnView()
                .tabItem { Label("Learn", systemImage: "book") }
                .tag(3)
        }
    }
}
