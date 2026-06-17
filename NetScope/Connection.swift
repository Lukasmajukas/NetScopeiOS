import SwiftUI
import Observation
import Network
import NetworkExtension
import MapKit
import CoreLocation
#if os(iOS)
import CoreTelephony
#endif

// MARK: - Live connection state
//
// Watches the active path (Wi-Fi vs Cellular), reads what little iOS exposes
// about the link — SSID/BSSID/signal on Wi-Fi (with the entitlement), and the
// radio access technology + Standalone/Non-Standalone on cellular via
// CoreTelephony — and resolves the public IP / carrier name from ipinfo.io.

@MainActor
@Observable
final class ConnectionMonitor {
    var networkType = "…"
    var online = false
    var expensive = false
    var localIP = ""

    // Wi-Fi
    var ssid = ""
    var bssid = ""
    var signalStrength = -1.0      // 0…1, -1 = unknown

    // Cellular (CoreTelephony)
    var cellGeneration = ""        // "5G", "4G LTE", "3G", "2G"
    var cellStandalone = ""        // "Standalone" / "Non-Standalone" / ""
    var cellTechRaw = ""           // e.g. "CTRadioAccessTechnologyNRNSA"

    // Public side (works on Wi-Fi and cellular)
    var publicIP = ""
    var isp = ""
    var city = ""
    var region = ""

    var isCellular: Bool { networkType == "Cellular" }

    /// Ookla-style connection type for the export ("Wi-Fi" / "Ethernet" / "5G" / "LTE" / …).
    var connType: String {
        switch networkType {
        case "Wi-Fi": return "Wi-Fi"
        case "Wired": return "Ethernet"
        case "Cellular":
            if cellGeneration.hasPrefix("5G") { return "5G" }
            if cellGeneration.contains("LTE") { return "LTE" }
            if cellGeneration.contains("3G") { return "3G" }
            if cellGeneration.contains("2G") { return "2G" }
            return "Cellular"
        default: return networkType
        }
    }

    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private var lastType = ""
    @ObservationIgnored private var ispTask: Task<Void, Never>?
    @ObservationIgnored private var ratTask: Task<Void, Never>?
    @ObservationIgnored private var ratObserver: NSObjectProtocol?
    @ObservationIgnored private var lastNRSeen: TimeInterval?   // systemUptime of last 5G sighting (monotonic)
    #if os(iOS)
    @ObservationIgnored private let cti = CTTelephonyNetworkInfo() // one persistent instance — required for live updates
    #endif

    init() {
        #if os(iOS)
        // Radio tech (LTE↔5G) often changes without an NWPath change, so refresh
        // on the system notification and on a light timer — keeps the badge current
        // and avoids the stale reads you get from a throwaway CTTelephonyNetworkInfo.
        ratObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("CTServiceRadioAccessTechnologyDidChangeNotification"),
            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.readCellular() }
        }
        ratTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                self?.readCellular()
            }
        }
        #endif
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                self.online = path.status == .satisfied
                self.expensive = path.isExpensive
                if path.usesInterfaceType(.wifi) { self.networkType = "Wi-Fi" }
                else if path.usesInterfaceType(.cellular) { self.networkType = "Cellular" }
                else if path.usesInterfaceType(.wiredEthernet) { self.networkType = "Wired" }
                else { self.networkType = self.online ? "Other" : "Offline" }

                self.localIP = Self.localIP(cellular: self.networkType == "Cellular") ?? ""
                self.readCellular()

                if self.networkType == "Wi-Fi" {
                    await self.refreshSSID()
                } else {
                    self.ssid = ""; self.bssid = ""; self.signalStrength = -1
                }

                // Re-resolve the public IP / carrier only when the link changes.
                if self.networkType != self.lastType {
                    self.lastType = self.networkType
                    self.publicIP = ""; self.isp = ""; self.city = ""; self.region = ""
                    if self.online { self.refreshPublicInfo() }
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "netscope.path"))
    }

    deinit {
        ratTask?.cancel()
        ispTask?.cancel()
        monitor.cancel()
        if let ratObserver { NotificationCenter.default.removeObserver(ratObserver) }
    }

    /// SSID/BSSID/signal — needs the "Access Wi-Fi Information" capability +
    /// Location permission; returns blanks without them, which is fine.
    func refreshSSID() async {
        #if os(iOS)
        let net: NEHotspotNetwork? = await withCheckedContinuation { cont in
            NEHotspotNetwork.fetchCurrent { cont.resume(returning: $0) }
        }
        if let net {
            if !net.ssid.isEmpty { ssid = net.ssid }
            bssid = net.bssid
            signalStrength = net.signalStrength
        }
        #endif
    }

    /// Current cellular radio access technology → friendly generation + SA/NSA.
    /// Picks the *data* SIM's radio (not a random dictionary entry), and holds a
    /// recent 5G reading briefly so a 5G-NSA handover dip to LTE doesn't make the
    /// badge flicker between "5G" and "4G LTE".
    private func readCellular() {
        #if os(iOS)
        let raw = currentRAT()

        // Off cellular: drop stale modem info so the UI doesn't show 5G on Wi-Fi.
        guard networkType == "Cellular" else {
            cellTechRaw = ""; cellGeneration = ""; cellStandalone = ""; lastNRSeen = nil
            return
        }
        guard !raw.isEmpty else { return }   // transient empty read — keep last known

        cellTechRaw = raw
        let gen = cellGenerationLabel(raw)
        let sa = cellStandaloneLabel(raw)
        let now = ProcessInfo.processInfo.systemUptime    // monotonic — immune to clock changes

        if gen == "5G" {
            lastNRSeen = now
            cellGeneration = gen
            cellStandalone = sa
        } else if let seen = lastNRSeen, now - seen < 8 {
            // Saw 5G within the last 8s but the live read dropped to LTE — that's
            // the classic NSA handover dip, so hold "5G · Non-Standalone" rather
            // than flickering to 4G (and don't keep asserting a stale "Standalone").
            cellGeneration = "5G"
            cellStandalone = "Non-Standalone"
        } else {
            cellGeneration = gen
            cellStandalone = sa
            lastNRSeen = nil
        }
        #endif
    }

    #if os(iOS)
    /// The radio access technology of the active data SIM, falling back to the
    /// first reported service only if the data SIM can't be identified. (No NR
    /// preference — that could over-report 5G from a non-data SIM on dual-SIM.)
    private func currentRAT() -> String {
        let dict = cti.serviceCurrentRadioAccessTechnology ?? [:]
        if let id = cti.dataServiceIdentifier, let rat = dict[id], !rat.isEmpty { return rat }
        return dict.values.first ?? ""
    }
    #endif

    private func refreshPublicInfo() {
        ispTask?.cancel()
        ispTask = Task { await fetchPublicInfo() }
    }

    /// ipinfo.io → public IP, ISP/carrier name, city/region. On cellular the
    /// "org" field reports the mobile carrier (CTCarrier is dead on iOS 16+).
    private func fetchPublicInfo() async {
        guard let url = URL(string: "https://ipinfo.io/json") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        guard let (d, _) = try? await URLSession.shared.data(for: req),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
        if Task.isCancelled { return }
        publicIP = (j["ip"] as? String) ?? ""
        city = (j["city"] as? String) ?? ""
        region = (j["region"] as? String) ?? ""
        let org = (j["org"] as? String) ?? ""
        if let r = org.range(of: #"^AS\d+\s+"#, options: .regularExpression) {
            isp = String(org[r.upperBound...])
        } else {
            isp = org
        }
    }

    /// Internal IP of the active interface: en0 (Wi-Fi) by default, or the
    /// cellular interface (pdp_ip0) when on mobile data. Prefers IPv4, but on
    /// cellular (often IPv6-only) it falls back to the interface's IPv6 address.
    static func localIP(cellular: Bool) -> String? {
        let wanted = cellular ? "pdp_ip0" : "en0"
        var v4: String?
        var v6: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = ptr {
            defer { ptr = cur.pointee.ifa_next }
            let flags = Int32(cur.pointee.ifa_flags)
            guard let sa = cur.pointee.ifa_addr,
                  (flags & (IFF_UP | IFF_RUNNING)) == (IFF_UP | IFF_RUNNING),
                  String(cString: cur.pointee.ifa_name) == wanted else { continue }
            let family = sa.pointee.sa_family
            guard family == UInt8(AF_INET) || family == UInt8(AF_INET6) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(sa, socklen_t(sa.pointee.sa_len),
                        &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            let addr = String(cString: host)
            if family == UInt8(AF_INET) { v4 = addr }
            else if v6 == nil, !addr.hasPrefix("fe80") { v6 = addr }  // skip link-local
        }
        freeifaddrs(ifaddr)
        return v4 ?? v6
    }
}

// Radio-access-technology constants carry their own name as their value
// (e.g. CTRadioAccessTechnologyNR == "CTRadioAccessTechnologyNR"), so we can
// classify by suffix without importing the framework into these helpers.
func cellGenerationLabel(_ raw: String) -> String {
    if raw.isEmpty { return "" }
    if raw.contains("NR") { return "5G" }                       // NR or NRNSA
    if raw.contains("LTE") { return "4G LTE" }
    if raw.contains("WCDMA") || raw.contains("HSDPA") || raw.contains("HSUPA")
        || raw.contains("CDMA") || raw.contains("HRPD") { return "3G" }
    if raw.contains("Edge") || raw.contains("GPRS") { return "2G" }
    return "Cellular"
}

func cellStandaloneLabel(_ raw: String) -> String {
    if raw.contains("NRNSA") { return "Non-Standalone" }        // 5G anchored to LTE
    if raw.contains("NR") { return "Standalone" }               // true 5G core
    return ""
}

// MARK: - Map (Apple Maps showing where you're connected)

@MainActor
@Observable
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    var status: CLAuthorizationStatus = .notDetermined
    var hasFix = false
    /// Latest fix, used to stamp speed-test results with lat/lon (nil until granted).
    var coordinate: CLLocationCoordinate2D?

    @ObservationIgnored private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        status = manager.authorizationStatus
    }

    func start() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        manager.startUpdatingLocation()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        Task { @MainActor in
            self.status = m.authorizationStatus
            #if os(iOS)
            if self.status == .authorizedWhenInUse || self.status == .authorizedAlways {
                m.startUpdatingLocation()
            }
            #else
            if self.status == .authorizedAlways { m.startUpdatingLocation() }
            #endif
        }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        guard let loc = locs.last else { return }
        Task { @MainActor in
            self.coordinate = loc.coordinate
            self.hasFix = true
        }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {}
}

struct ConnectionMap: View {
    @Environment(LocationProvider.self) private var loc

    // The camera is owned by the view (the modern MapKit-SwiftUI pattern) and
    // animates to each new fix, rather than the model holding an MKCoordinateRegion.
    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090),
                           span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)))

    var body: some View {
        ZStack {
            Map(position: $camera) {
                UserAnnotation()
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
            if loc.status == .denied || loc.status == .restricted {
                VStack(spacing: 6) {
                    Image(systemName: "location.slash").font(.title3)
                    Text("Allow Location in Settings to see where you’re connected.")
                        .font(.caption).multilineTextAlignment(.center)
                }
                .foregroundStyle(Color.nsMuted)
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(24)
            } else if !loc.hasFix {
                ProgressView().tint(.white)
            }
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.nsLine, lineWidth: 1))
        .onAppear { loc.start() }
        .onChange(of: loc.coordinate?.latitude) { _, _ in
            guard let c = loc.coordinate else { return }
            withAnimation(.easeInOut(duration: 0.6)) {
                camera = .region(MKCoordinateRegion(
                    center: c, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)))
            }
        }
    }
}

// MARK: - View

struct ConnectionView: View {
    @Environment(ConnectionMonitor.self) private var conn
    @Environment(HistoryStore.self) private var history
    @Environment(ProManager.self) private var pro
    @State private var enrich = EnrichmentClient()
    @AppStorage("enrichEndpoint") private var enrichEndpoint = ""
    @AppStorage("enrichToken")    private var enrichToken    = ""

    var body: some View {
        Screen("Connection") {
            hero
            if conn.isCellular { cellularDetail } else { wifiDetail }
            mapCard
            internetCard
            ispServiceSection
            note
        }
        // Re-run when Pro flips on AND when the public IP finally resolves
        // (ipinfo loads async — without the IP a configured endpoint can't query).
        .task(id: "\(pro.isPro)|\(conn.publicIP)") { await loadEnrichment() }
    }

    @ViewBuilder
    private var ispServiceSection: some View {
        if pro.isPro {
            ISPServiceCard(lastDownload: history.items.first?.downloadMbps,
                           enrichment: enrich.result,
                           isSample: enrich.isSample)
        } else {
            ProLockedCard(
                title: "ISP Service",
                blurb: "See your provisioned plan speed, connection technology, and whether the line is throttled — modelled on Ookla's provider enrichment data.",
                icon: "building.2.crop.circle")
        }
    }

    private func loadEnrichment() async {
        guard pro.isPro else { return }
        await enrich.load(endpoint: enrichEndpoint, token: enrichToken,
                          ipv4: conn.publicIP)
    }

    // Hero

    private var hero: some View {
        Card {
            HStack(spacing: 14) {
                Image(systemName: conn.isCellular
                      ? "antenna.radiowaves.left.and.right" : "wifi")
                    .font(.system(size: 30))
                    .foregroundStyle(conn.online ? Color.nsOk : Color.nsFaint)
                    .contentTransition(.symbolEffect(.replace))   // smooth swap wifi↔antenna
                    .symbolEffect(.variableColor.iterative, isActive: !conn.online) // "searching" pulse
                    .animation(.smooth, value: conn.online)
                VStack(alignment: .leading, spacing: 2) {
                    Text(heroTitle)
                        .font(.title2.weight(.semibold)).foregroundStyle(Color.nsTxt)
                        .contentTransition(.numericText())
                    Text(heroSub).font(.caption).foregroundStyle(Color.nsMuted)
                }
                Spacer()
            }
            .animation(.smooth, value: heroTitle)
        }
    }

    private var heroTitle: String {
        if !conn.online { return "Offline" }
        if conn.isCellular { return conn.cellGeneration.isEmpty ? "Cellular" : conn.cellGeneration }
        return "Wi-Fi"
    }

    private var heroSub: String {
        if !conn.online { return "No connection" }
        if conn.isCellular {
            return conn.cellStandalone.isEmpty ? "Mobile data" : "5G · \(conn.cellStandalone)"
        }
        return conn.ssid.isEmpty ? "Connected" : conn.ssid
    }

    // Cellular

    private var cellularDetail: some View {
        Group {
            Card("Modem") {
                row("Generation", conn.cellGeneration.isEmpty ? "—" : conn.cellGeneration)
                if !conn.cellStandalone.isEmpty {
                    row("5G mode", conn.cellStandalone)
                }
                row("Radio type", techPretty)
                row("Carrier", conn.isp.isEmpty ? "…" : conn.isp)
                row("Data cost", conn.expensive ? "Metered" : "Unmetered")
            }
            if !conn.cellStandalone.isEmpty {
                Card {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "info.circle").foregroundStyle(Color.nsAccent)
                        Text(conn.cellStandalone == "Standalone"
                             ? "Standalone 5G runs on a pure 5G core — lower latency and the full benefit of 5G."
                             : "Non-Standalone 5G rides on the existing 4G core for signalling. Common today; speeds are 5G but latency is closer to LTE.")
                            .font(.caption).foregroundStyle(Color.nsMuted)
                    }
                }
            }
        }
    }

    private var techPretty: String {
        let r = conn.cellTechRaw
        guard !r.isEmpty else { return "—" }
        // Strip the "CTRadioAccessTechnology" prefix for display.
        return r.replacingOccurrences(of: "CTRadioAccessTechnology", with: "")
    }

    // Wi-Fi

    private var wifiDetail: some View {
        Group {
            if conn.signalStrength >= 0 { signalCard }
            bandsCard
            Card("Details") {
                row("Network", conn.ssid.isEmpty ? "Wi-Fi" : conn.ssid)
                if !conn.bssid.isEmpty { row("Router (BSSID)", conn.bssid) }
                row("Local IP", conn.localIP.isEmpty ? "—" : conn.localIP)
                row("Data cost", conn.expensive ? "Metered" : "Unmetered")
            }
        }
    }

    private var signalCard: some View {
        Card("Signal") {
            HStack(spacing: 12) {
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(0..<4, id: \.self) { i in
                        let on = conn.signalStrength >= Double(i + 1) / 4.0 - 0.12
                        RoundedRectangle(cornerRadius: 2)
                            .fill(on ? Color.nsOk : Color.nsLine)
                            .frame(width: 8, height: 10 + CGFloat(i) * 8)
                    }
                }
                .animation(.snappy, value: conn.signalStrength)
                Text("\(Int((conn.signalStrength * 100).rounded()))%")
                    .font(.title3.weight(.semibold)).foregroundStyle(Color.nsTxt)
                    .contentTransition(.numericText())
                Spacer()
            }
        }
    }

    private var bandsCard: some View {
        Card("Wi-Fi bands") {
            Text("iOS won’t tell an app which band it’s on, so here’s what each one means — plus a best guess from your latest speed test.")
                .font(.caption).foregroundStyle(Color.nsMuted)
            bandRow(.nsB24, "2.4 GHz", "Best range, through walls · slowest · most crowded")
            bandRow(.nsB5, "5 GHz", "Fast · medium range · what most devices use")
            bandRow(.nsB6, "6 GHz", "Fastest · short range · Wi-Fi 6E / 7 only")
            if let guess = bandGuess {
                Divider().overlay(Color.nsLine)
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "sparkles").foregroundStyle(Color.nsAccent)
                    Text(guess).font(.caption).foregroundStyle(Color.nsTxt)
                }
            }
        }
    }

    private func bandRow(_ color: Color, _ name: String, _ desc: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(color).frame(width: 9, height: 9).padding(.top, 5)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.subheadline.weight(.semibold)).foregroundStyle(Color.nsTxt)
                Text(desc).font(.caption).foregroundStyle(Color.nsMuted)
            }
            Spacer()
        }
    }

    private var bandGuess: String? {
        guard let r = history.items.first(where: { $0.network == "Wi-Fi" && $0.downloadMbps > 0 })
        else { return nil }
        let d = Int(r.downloadMbps.rounded())
        let band: String
        if r.downloadMbps < 90 { band = "the 2.4 GHz band" }
        else if r.downloadMbps <= 500 { band = "the 5 GHz band" }
        else { band = "5 GHz or 6 GHz" }
        return "Your last test hit \(d) Mbps — likely on \(band)."
    }

    // Shared

    private var mapCard: some View {
        Card(conn.isCellular ? "Where you are" : "Where this network is") {
            ConnectionMap()
            if !conn.city.isEmpty {
                Label(conn.region.isEmpty ? conn.city : "\(conn.city), \(conn.region)",
                      systemImage: "mappin.and.ellipse")
                    .font(.caption).foregroundStyle(Color.nsMuted)
            }
        }
    }

    private var internetCard: some View {
        Card("Internet") {
            row("Status", conn.online ? "Online" : "Offline")
            row("Public IP", conn.publicIP.isEmpty ? "…" : conn.publicIP)
            row(conn.isCellular ? "Carrier" : "ISP", conn.isp.isEmpty ? "…" : conn.isp)
        }
    }

    private var note: some View {
        Card {
            Text(conn.isCellular
                 ? "On mobile data the device finder is hidden — there’s no browsable local network to scan. iOS limits modem detail to the radio type shown above; signal bars, cell ID and band aren’t available to apps."
                 : "iOS hides most Wi-Fi detail from apps. The network name, BSSID and signal only appear with the “Access Wi-Fi Information” capability + Location permission; band, channel and width aren’t exposed to third-party apps at all.")
                .font(.caption).foregroundStyle(Color.nsFaint)
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).foregroundStyle(Color.nsMuted)
            Spacer()
            Text(v).foregroundStyle(Color.nsTxt).monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.vertical, 5)
        .overlay(alignment: .bottom) { Divider().overlay(Color.nsLine) }
    }
}
