import SwiftUI
import Observation
import Network

struct FoundDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let kind: String
    let serviceType: String
}

@MainActor
@Observable
final class DeviceBrowser {
    private(set) var devices: [FoundDevice] = []
    private(set) var scanning = false

    @ObservationIgnored private var browsers: [NWBrowser] = []
    // Keyed by device name; priority = index in `services` (most-specific first),
    // so a device that advertises several services shows once with its best label.
    @ObservationIgnored private var found: [String: (device: FoundDevice, priority: Int)] = [:]

    // Common Bonjour service types and a friendly label for each.
    private let services: [(String, String)] = [
        ("_airplay._tcp", "AirPlay (Apple TV / speaker)"),
        ("_raop._tcp", "AirPlay audio"),
        ("_googlecast._tcp", "Chromecast / Google TV"),
        ("_spotify-connect._tcp", "Spotify device"),
        ("_sonos._tcp", "Sonos"),
        ("_ipp._tcp", "Printer"),
        ("_printer._tcp", "Printer"),
        ("_pdl-datastream._tcp", "Printer"),
        ("_hap._tcp", "HomeKit accessory"),
        ("_companion-link._tcp", "Apple device"),
        ("_device-info._tcp", "Computer / NAS"),
        ("_smb._tcp", "File share (SMB)"),
        ("_afpovertcp._tcp", "Mac file share"),
        ("_ssh._tcp", "SSH host"),
        ("_http._tcp", "Web service"),
        ("_amzn-wplay._tcp", "Amazon device"),
        ("_nvstream._tcp", "NVIDIA Shield")
    ]

    func start() {
        stop()
        scanning = true
        found = [:]
        devices = []
        for (priority, (type, label)) in services.enumerated() {
            let browser = NWBrowser(for: .bonjour(type: type, domain: nil), using: NWParameters())
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                Task { @MainActor in
                    guard let self else { return }
                    for result in results {
                        if case let .service(name, t, _, _) = result.endpoint {
                            let key = name.lowercased()
                            if let existing = self.found[key], existing.priority <= priority { continue }
                            self.found[key] = (FoundDevice(id: key, name: name,
                                                           kind: label, serviceType: t), priority)
                        }
                    }
                    let list = self.found.values.map(\.device)
                        .sorted { $0.name.lowercased() < $1.name.lowercased() }
                    withAnimation(.easeInOut(duration: 0.25)) { self.devices = list }
                }
            }
            browser.start(queue: .main)
            browsers.append(browser)
        }
    }

    func stop() {
        browsers.forEach { $0.cancel() }
        browsers = []
        scanning = false
    }
}

struct DevicesView: View {
    @State private var browser = DeviceBrowser()

    var body: some View {
        Screen("Devices") {
            Card {
                Label {
                    Text("iOS only lets apps discover devices that **advertise a service** (Bonjour/mDNS) — Apple TVs, printers, Chromecasts, HomePods, NAS, some smart-home gear. It cannot do a full ARP/ping sweep or read MAC addresses, so this list is shorter than the Mac app’s.")
                        .font(.caption).foregroundStyle(Color.nsMuted)
                } icon: {
                    Image(systemName: "info.circle").foregroundStyle(Color.nsAccent)
                }
            }

            Card("Found (\(browser.devices.count))") {
                if browser.devices.isEmpty {
                    ContentUnavailableView {
                        Label(browser.scanning ? "Listening for devices…" : "No devices yet",
                              systemImage: "dot.radiowaves.left.and.right")
                            .symbolEffect(.variableColor.iterative, isActive: browser.scanning)
                    } description: {
                        Text(browser.scanning
                             ? "Looking for Bonjour services on your Wi-Fi."
                             : "Tap Scan to look for devices on your network.")
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    ForEach(browser.devices) { d in
                        HStack(spacing: 12) {
                            Image(systemName: icon(for: d.serviceType))
                                .foregroundStyle(Color.nsAccent).frame(width: 26)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(d.name).foregroundStyle(Color.nsTxt)
                                Text(d.kind).font(.caption2).foregroundStyle(Color.nsFaint)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 6)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                        .overlay(alignment: .bottom) { Divider().overlay(Color.nsLine) }
                    }
                }
                Button {
                    browser.scanning ? browser.stop() : browser.start()
                } label: {
                    Label(browser.scanning ? "Stop" : "Scan",
                          systemImage: browser.scanning ? "stop.circle" : "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .symbolEffect(.rotate, options: .repeating, isActive: browser.scanning)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(Color.nsSurface2, in: RoundedRectangle(cornerRadius: 10))
                }
                .padding(.top, 4)
            }
        }
        .onAppear { if browser.devices.isEmpty { browser.start() } }
        .onDisappear { browser.stop() }
    }

    private func icon(for type: String) -> String {
        switch type {
        case let t where t.contains("airplay") || t.contains("raop"): return "appletv"
        case let t where t.contains("googlecast"): return "tv"
        case let t where t.contains("print") || t.contains("ipp") || t.contains("pdl"): return "printer"
        case let t where t.contains("hap") || t.contains("homekit"): return "homekit"
        case let t where t.contains("sonos") || t.contains("spotify"): return "hifispeaker"
        case let t where t.contains("smb") || t.contains("afp") || t.contains("device-info"): return "externaldrive"
        case let t where t.contains("ssh") || t.contains("http"): return "server.rack"
        default: return "dot.radiowaves.left.and.right"
        }
    }
}
