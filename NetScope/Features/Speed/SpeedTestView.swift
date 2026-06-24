import SwiftUI
import Charts

struct SpeedGauge: View {
    var value: Double
    var scale: Double
    var color: Color
    var label: String
    var progress: Double = 0

    private var frac: Double { scale > 0 ? max(0, min(1, value / scale)) : 0 }

    var body: some View {
        ZStack {
            // tick marks
            ForEach(0..<28, id: \.self) { i in
                Rectangle()
                    .fill(i % 9 == 0 ? Color.nsFaint : Color.nsLine)
                    .frame(width: 2, height: i % 9 == 0 ? 11 : 6)
                    .offset(y: -86)
                    .rotationEffect(.degrees(135 + Double(i) * (270.0 / 27.0)))
            }
            // track (270° arc, gap centred at the bottom)
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(Color.nsSurface2, style: .init(lineWidth: 13, lineCap: .round))
                .rotationEffect(.degrees(135))
            // value
            Circle()
                .trim(from: 0, to: 0.75 * frac)
                .stroke(color, style: .init(lineWidth: 13, lineCap: .round))
                .rotationEffect(.degrees(135))
                .shadow(color: color.opacity(0.55), radius: 7)
                .animation(.spring(response: 0.5, dampingFraction: 0.82), value: frac)
                .animation(.smooth(duration: 0.4), value: color)
            // thin inner ring showing progress through the current phase
            Circle()
                .trim(from: 0, to: 0.75 * max(0, min(1, progress)))
                .stroke(color.opacity(0.55), style: .init(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(135))
                .frame(width: 186, height: 186)
                .animation(.snappy(duration: 0.3), value: progress)
            VStack(spacing: 2) {
                Text(value >= 100 ? String(Int(value.rounded())) : String(format: "%.1f", value))
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(Color.nsTxt)
                Text("Mbps").font(.subheadline).foregroundStyle(Color.nsMuted)
                Text(label.uppercased())
                    .font(.caption2).tracking(1.8)
                    .foregroundStyle(label.isEmpty ? .clear : Color.nsFaint)
                    .padding(.top, 6)
            }
        }
        .frame(width: 220, height: 220)
        .padding(.vertical, 4)
    }
}

struct SpeedTestView: View {
    @State private var engine = SpeedTestEngine()
    @State private var directory = ServerDirectory()
    @State private var summarizer = AISummarizer()
    @Environment(HistoryStore.self) private var history
    @Environment(ConnectionMonitor.self) private var connection
    @Environment(LocationProvider.self) private var location
    @Environment(ProManager.self) private var pro
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    // One-time informed consent before the first M-Lab test, since M-Lab
    // publishes every test (incl. the user's IP) as open data. Bump the key
    // suffix if the disclosure text materially changes, to re-prompt.
    // One-time informed consent before the first test against each external backbone
    // (M-Lab publishes results as open data; LibreSpeed servers are third-party donated
    // hosts). Cloudflare needs none. Bump the key suffix if the disclosure text changes.
    @AppStorage("mlabConsentAcceptedV1") private var mlabConsented = false
    @AppStorage("libreConsentAcceptedV1") private var libreConsented = false
    @AppStorage("cmConsentAcceptedV1") private var cmConsented = false
    @State private var showConsent = false
    @State private var consentProvider: SpeedServer.Provider = .mlab

    /// Starts a test, but routes the first M-Lab run through a consent prompt
    /// Whether running against this provider still needs a one-time consent prompt.
    private func needsConsent(_ p: SpeedServer.Provider) -> Bool {
        switch p {
        case .cloudflare:  return false             // anycast, not published, not third-party
        case .mlab:        return !mlabConsented
        case .librespeed:  return !libreConsented
        case .coveragemap: return !cmConsented
        }
    }

    /// Routes the first run against any external backbone (M-Lab or LibreSpeed) through
    /// its consent prompt; Cloudflare runs immediately.
    private func startTest() {
        let server = directory.selected
        if needsConsent(server.provider) {
            consentProvider = server.provider
            showConsent = true
            return
        }
        engine.start(runContext(), server: server)
    }

    /// Auto-start a test without ever showing the consent prompt — used by Shortcuts/Siri
    /// automation. Silently skips when a test is running or the selected backbone still
    /// needs consent (the default is Cloudflare, which never does).
    private func autoRunIfAllowed() {
        Task {
            try? await Task.sleep(nanoseconds: 600_000_000)   // let the path monitor settle
            let s = directory.selected
            if !engine.running && !needsConsent(s.provider) {
                engine.start(runContext(), server: s)
            }
        }
    }

    /// Consume the one-shot flag set by the Siri "Run Speed Test" App Intent.
    private func consumeSiriRun() {
        guard UserDefaults.standard.bool(forKey: kSiriRunFlag) else { return }
        UserDefaults.standard.set(false, forKey: kSiriRunFlag)
        autoRunIfAllowed()
    }

    /// Snapshot of the current connection used to stamp the saved result.
    private func runContext() -> SpeedTestEngine.RunContext {
        SpeedTestEngine.RunContext(
            network: connection.networkType,
            ssid: connection.ssid,
            connType: connection.connType,
            localIP: connection.localIP,
            lat: location.coordinate?.latitude,
            lon: location.coordinate?.longitude)
    }

    private var gaugeColor: Color {
        switch engine.phase {
        case .downloading, .done: return .nsOk
        case .uploading: return .nsAccent
        default: return .nsFaint
        }
    }

    private var gearButton: some View {
        Button { showSettings = true } label: {
            Image(systemName: "gear").foregroundStyle(Color.nsAccent)
        }
    }

    var body: some View {
        Screen("Speed", trailing: gearButton) {
            Card {
                ispLine
                SpeedGauge(value: engine.live, scale: engine.scaleMax,
                           color: gaugeColor, label: engine.phase.rawValue,
                           progress: engine.progress)
                    .frame(maxWidth: .infinity)
                HStack(spacing: 10) {
                    metric("Download", engine.download, .nsOk, active: engine.phase == .downloading)
                    metric("Upload", engine.upload, .nsAccent, active: engine.phase == .uploading)
                }
                metric("Ping", engine.ping, .nsB6, unit: "ms",
                       sub: engine.jitter > 0 ? "jitter \(fmt(engine.jitter)) ms" : "",
                       active: engine.phase == .latency)
                if engine.phase == .failed { failedNote }
                runButton
            }
            aiCard
            serverCard
            trendCard
            historyCard
            coverageCard
        }
        .task {
            // Discover Cloudflare + nearby M-Lab locations and ping them once.
            if directory.servers.count <= 1 { await directory.refresh() }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(history)
                .environment(location)
                .environment(pro)
        }
        .sheet(isPresented: $showConsent) {
            ServerConsentSheet(
                provider: consentProvider,
                place: directory.selected.shortPlace,
                onAgree: {
                    switch consentProvider {
                    case .mlab:        mlabConsented = true
                    case .librespeed:  libreConsented = true
                    case .coveragemap: cmConsented = true
                    case .cloudflare:  break
                    }
                    showConsent = false
                    engine.start(runContext(), server: directory.selected)
                },
                onCancel: { showConsent = false })
        }
        .onAppear {
            // A new saved result invalidates any prior AI summary.
            engine.onFinished = { history.add($0); summarizer.reset() }
            location.start()   // warm up location so a finished test can record lat/lon
            summarizer.refreshAvailability()
            consumeSiriRun()
            // Launch-only autorun (`-autorun 1` / Shortcuts automation).
            if UserDefaults.standard.bool(forKey: "autorun") { autoRunIfAllowed() }
        }
        .onChange(of: scenePhase) { _, phase in
            // Siri can foreground an app that's ALREADY open (onAppear won't refire), so
            // also consume the run flag when the scene becomes active.
            if phase == .active { consumeSiriRun() }
        }
        // Declarative haptics keyed to the test phase (replaces manual generators).
        .sensoryFeedback(trigger: engine.phase) { _, new in
            switch new {
            case .latency, .downloading, .uploading: return .impact(weight: .light)
            case .done:   return .success
            case .failed: return .warning
            default:      return nil
            }
        }
    }

    // MARK: pieces

    private var ispLine: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Provider: \(engine.info.isp.isEmpty ? "—" : engine.info.isp)")
                .foregroundStyle(Color.nsTxt)
            HStack(spacing: 6) {
                if !engine.info.ip.isEmpty { Text("IP \(engine.info.ip)") }
                if !engine.info.server.isEmpty { Text("· \(engine.info.server)") }
            }
            .foregroundStyle(Color.nsMuted)
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metric(_ title: String, _ value: Double, _ color: Color,
                        unit: String = "Mbps", sub: String = "", active: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased()).font(.caption2).tracking(0.8).foregroundStyle(Color.nsMuted)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value > 0 ? (value >= 100 ? String(Int(value.rounded())) : fmt(value)) : "—")
                    .font(.title2.weight(.semibold)).monospacedDigit().foregroundStyle(Color.nsTxt)
                    .contentTransition(.numericText())
                Text(unit).font(.caption).foregroundStyle(Color.nsMuted)
            }
            Text(sub).font(.caption2).foregroundStyle(Color.nsFaint)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.nsSurface2, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(active ? color : .clear, lineWidth: 1.5))
        .overlay(alignment: .leading) {
            Rectangle().fill(color).frame(width: 3).clipShape(RoundedRectangle(cornerRadius: 2))
        }
        .scaleEffect(active ? 1.02 : 1)
        .animation(.smooth(duration: 0.25), value: active)
    }

    private var failedNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.exclamationmark").foregroundStyle(Color(hex: 0xff6b6b))
            Text("Couldn't reach the server. Check your connection and try again — nothing was saved.")
                .font(.caption).foregroundStyle(Color.nsTxt)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color(hex: 0xff6b6b).opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .transition(.opacity)
    }

    private var runButton: some View {
        Button {
            startTest()
        } label: {
            HStack(spacing: 8) {
                if engine.running { ProgressView().tint(.black) }
                Image(systemName: "speedometer")
                    .symbolEffect(.variableColor.iterative, isActive: engine.running)
                Text(engine.running ? engine.phase.rawValue.capitalized + "…" : "Run speed test")
                    .fontWeight(.semibold)
                    .contentTransition(.opacity)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 14)
            .foregroundStyle(Color(hex: 0x04122e))
            .background(Color.nsAccent, in: Capsule())
        }
        .disabled(engine.running)
        .opacity(engine.running ? 0.9 : 1)
        .padding(.top, 4)
    }

    // MARK: Server / location picker

    // MARK: Apple Intelligence summary

    @ViewBuilder
    private var aiCard: some View {
        // Only when on-device Apple Intelligence is available and there's a result to read.
        if summarizer.available, let latest = history.items.first {
            Card {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Color.nsAccent)
                        .symbolEffect(.variableColor.iterative, isActive: summarizer.state == .generating)
                    Text("APPLE INTELLIGENCE")
                        .font(.caption2.weight(.semibold)).tracking(1.1).foregroundStyle(Color.nsMuted)
                    Spacer()
                }
                switch summarizer.state {
                case .idle:
                    Button { Task { await summarizer.summarize(latest) } } label: {
                        Text("Summarise my connection").font(.caption.weight(.semibold))
                            .foregroundStyle(Color.nsAccent)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .nsGlassCapsule()
                    }
                case .generating:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Thinking on-device…").font(.caption).foregroundStyle(Color.nsFaint)
                    }
                case .done(let text):
                    Text(text).font(.subheadline).foregroundStyle(Color.nsTxt)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Regenerate") { Task { await summarizer.summarize(latest) } }
                        .font(.caption2).foregroundStyle(Color.nsFaint)
                case .failed(let msg):
                    Text(msg).font(.caption).foregroundStyle(Color.nsFaint)
                }
                Text("Generated on-device by Apple Intelligence — nothing leaves your iPhone.")
                    .font(.caption2).foregroundStyle(Color.nsFaint)
            }
        }
    }

    private var serverCard: some View {
        Card {
            HStack {
                Text("TEST SERVER")
                    .font(.caption2.weight(.semibold)).tracking(1.1).foregroundStyle(Color.nsMuted)
                Spacer()
                Button { Task { await directory.refresh(repingLibre: true) } } label: {
                    Image(systemName: "arrow.clockwise")
                        .symbolEffect(.rotate, options: .repeating, isActive: directory.loading)
                        .foregroundStyle(Color.nsAccent)
                }
                .disabled(directory.loading)
            }
            // M-Lab can return servers for a chosen country, not just the nearest.
            HStack {
                Text("M-Lab country").font(.caption).foregroundStyle(Color.nsMuted)
                Spacer()
                Menu {
                    ForEach(ServerDirectory.countries, id: \.name) { c in
                        Button {
                            if directory.mlabCountry != c.code {
                                directory.mlabCountry = c.code
                                Task { await directory.refresh() }
                            }
                        } label: {
                            if directory.mlabCountry == c.code { Label(c.name, systemImage: "checkmark") }
                            else { Text(c.name) }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(mlabCountryName).font(.caption.weight(.semibold))
                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }
                    .foregroundStyle(Color.nsAccent)
                }
                .disabled(directory.loading)
            }
            if directory.servers.count <= 1 && directory.loading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Finding nearby servers…").font(.caption).foregroundStyle(Color.nsFaint)
                }
            }
            ForEach(directory.servers) { serverRow($0) }
            Text("Throughput runs on Cloudflare's nearest edge, M-Lab / NDT7, LibreSpeed, or CoverageMap — open measurement networks. Pick a city (or an M-Lab country) to test a specific route; ping shows the TCP round-trip to each.")
                .font(.caption2).foregroundStyle(Color.nsFaint)
        }
        .disabled(engine.running)
        .opacity(engine.running ? 0.6 : 1)
    }

    private func serverRow(_ s: SpeedServer) -> some View {
        let isSelected = directory.selectedID == s.id
        return Button { directory.selectedID = s.id } label: {
            HStack(spacing: 12) {
                Image(systemName: providerIcon(s.provider))
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Color.nsAccent : Color.nsFaint)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.shortPlace).font(.subheadline.weight(.medium)).foregroundStyle(Color.nsTxt)
                    Text(s.detail).font(.caption2).foregroundStyle(Color.nsFaint)
                }
                Spacer()
                Text(pingText(s.pingMs)).font(.caption.monospacedDigit())
                    .foregroundStyle(latencyColor(s.pingMs))
                    .contentTransition(.numericText())
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.nsAccent : Color.nsLine)
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Divider().overlay(Color.nsLine) }
    }

    private var mlabCountryName: String {
        ServerDirectory.countries.first { $0.code == directory.mlabCountry }?.name ?? "Nearest"
    }

    private func providerIcon(_ p: SpeedServer.Provider) -> String {
        switch p {
        case .cloudflare:  return "bolt.horizontal.circle.fill"
        case .mlab:        return "globe.americas.fill"
        case .librespeed:  return "server.rack"
        case .coveragemap: return "map.circle.fill"
        }
    }

    private func pingText(_ ms: Double?) -> String {
        guard let ms else { return directory.loading ? "…" : "—" }
        return "\(Int(ms.rounded())) ms"
    }
    private func latencyColor(_ ms: Double?) -> Color {
        guard let ms else { return Color.nsFaint }
        if ms < 50 { return .nsOk }
        if ms < 150 { return Color(hex: 0xffa726) }
        return Color(hex: 0xff6b6b)
    }

    @ViewBuilder
    private var coverageCard: some View {
        if pro.isPro {
            NavigationLink(destination: CoverageMapView()) {
                Card {
                    HStack(spacing: 14) {
                        Image(systemName: "map.fill")
                            .font(.system(size: 24)).foregroundStyle(Color.nsAccent)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text("Coverage Map")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.nsTxt)
                                ProBadge()
                            }
                            Text("Your speed tests, mapped as coloured tiles.")
                                .font(.caption).foregroundStyle(Color.nsMuted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold)).foregroundStyle(Color.nsFaint)
                    }
                }
            }
            .buttonStyle(.plain)
        } else {
            ProLockedCard(
                title: "Coverage Map",
                blurb: "Map every speed test as a coloured tile and build a personal coverage heatmap — optionally merged across devices through a Mac.",
                icon: "map.fill")
        }
    }

    // MARK: Trend (Swift Charts)

    private struct TrendPoint: Identifiable {
        let id = UUID(); let date: Date; let down: Double; let up: Double
    }
    private var trendData: [TrendPoint] {
        history.items.sorted { $0.date < $1.date }.suffix(30).map {
            TrendPoint(date: $0.date, down: $0.downloadMbps, up: max(0, $0.uploadMbps))
        }
    }

    @ViewBuilder
    private var trendCard: some View {
        if history.items.count >= 2 {
            Card("Trend") {
                Chart {
                    ForEach(trendData) { p in
                        LineMark(x: .value("Time", p.date), y: .value("Mbps", p.down))
                            .foregroundStyle(by: .value("Series", "Download"))
                            .interpolationMethod(.catmullRom)
                        AreaMark(x: .value("Time", p.date), y: .value("Mbps", p.down))
                            .foregroundStyle(LinearGradient(
                                colors: [Color.nsOk.opacity(0.22), .clear],
                                startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("Time", p.date), y: .value("Mbps", p.up))
                            .foregroundStyle(by: .value("Series", "Upload"))
                            .interpolationMethod(.catmullRom)
                    }
                }
                .chartForegroundStyleScale(["Download": Color.nsOk, "Upload": Color.nsAccent])
                .chartYAxis { AxisMarks(position: .leading) }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
                .chartLegend(position: .top, alignment: .leading)
                .frame(height: 170)
                .animation(.smooth, value: history.items.count)
            }
        }
    }

    private var historyCard: some View {
        Card("History (\(history.items.count) saved)") {
            if history.items.isEmpty {
                ContentUnavailableView("No tests yet", systemImage: "speedometer",
                    description: Text("Run a test above — results are kept here and export as CSV."))
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(Array(history.items.prefix(maxRows))) { r in historyRow(r) }
                if history.items.count > maxRows {
                    Text("Showing the latest \(maxRows) of \(history.items.count) — export CSV for the full set.")
                        .font(.caption2).foregroundStyle(Color.nsFaint).padding(.top, 2)
                }
                HStack {
                    if let url = history.csvFileURL() {
                        ShareLink(item: url) {
                            Label("Export CSV", systemImage: "square.and.arrow.up")
                                .font(.caption.weight(.semibold))
                        }
                    }
                    Spacer()
                    Button("Clear", role: .destructive) { history.clear() }
                        .font(.caption)
                }
                .padding(.top, 4)
            }
        }
    }

    private func historyRow(_ r: SpeedResult) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(r.date, format: .dateTime.month().day().hour().minute())
                    .font(.caption).foregroundStyle(Color.nsMuted)
                Text(networkLabel(r)).font(.caption2).foregroundStyle(Color.nsFaint)
            }
            Spacer()
            Text("▼ \(speedLabel(r.downloadMbps))").foregroundStyle(Color.nsOk)
            Text("▲ \(speedLabel(r.uploadMbps))").foregroundStyle(Color.nsAccent)
            Text("\(Int(r.pingMs.rounded())) ms").foregroundStyle(Color.nsFaint)
                .frame(width: 56, alignment: .trailing)
        }
        .font(.caption.weight(.medium)).monospacedDigit()
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) { Divider().overlay(Color.nsLine) }
    }

    private func networkLabel(_ r: SpeedResult) -> String {
        let type = r.connType ?? r.network
        let place = !r.ssid.isEmpty ? r.ssid : (r.serverCity ?? "")
        return place.isEmpty ? type : "\(type) · \(place)"
    }
    private func speedLabel(_ v: Double) -> String { v >= 100 ? "\(Int(v.rounded()))" : fmt(v) }
    private func fmt(_ v: Double) -> String { String(format: "%.1f", v) }

    private let maxRows = 40
}

// MARK: - M-Lab open-data consent

/// One-time informed-consent sheet shown before the first M-Lab speed test.
/// M-Lab publishes every test (including the user's IP, the time, and the
/// measured speeds) as an open, CC0-licensed public dataset — so this names
/// that consequence plainly and requires an affirmative tap before any run.
struct ServerConsentSheet: View {
    let provider: SpeedServer.Provider
    let place: String
    let onAgree: () -> Void
    let onCancel: () -> Void

    private var icon: String {
        switch provider {
        case .mlab: return "globe.americas.fill"
        case .coveragemap: return "map.circle.fill"
        default: return "server.rack"
        }
    }
    private var network: String {
        switch provider {
        case .mlab: return "M-Lab"
        case .coveragemap: return "CoverageMap"
        default: return "LibreSpeed"
        }
    }
    private var title: String {
        switch provider {
        case .mlab: return "Public measurement"
        case .coveragemap: return "Coverage contribution"
        default: return "Third-party server"
        }
    }
    private var lead: String {
        switch provider {
        case .mlab:
            return "You picked an **M-Lab** server. M-Lab is an open research network — it makes internet performance data public so anyone can study it."
        case .coveragemap:
            return "You picked a **CoverageMap** server. CoverageMap builds a crowd-sourced map of network coverage from speed tests."
        default:
            return "You picked a **LibreSpeed** server. These are community-donated servers run by third parties (ISPs, hosts), **not operated by NetScope**."
        }
    }
    private var bullets: [String] {
        switch provider {
        case .mlab:
            return ["Running this test publishes your **public IP address**, the **time**, and your **measured speeds** as open data under a CC0 (public-domain) license.",
                    "This is done by M-Lab, not by NetScope — and once published, **it cannot be undone or deleted**.",
                    "Prefer to keep tests private? Tap **Cancel** and choose the **Cloudflare** server instead — it isn't published."]
        case .coveragemap:
            return ["Running this test sends your **public IP address** and test traffic to a CoverageMap server.",
                    "Your **result** — IP, approximate location, and measured speeds — is **uploaded to CoverageMap** to contribute to its public coverage map.",
                    "Prefer not to contribute? Tap **Cancel** and choose **Cloudflare** — it stays on your device."]
        default:
            return ["Running this test sends your **public IP address** and full-rate test traffic to a **third-party server NetScope doesn't control**.",
                    "The result isn't published as an open dataset, but the host operator can see your IP and connection — treat it like visiting any third-party website.",
                    "Prefer to stick with a first-party backbone? Tap **Cancel** and choose **Cloudflare**."]
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 14) {
                        Image(systemName: icon)
                            .font(.system(size: 30)).foregroundStyle(Color.nsAccent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .font(.title3.weight(.bold)).foregroundStyle(Color.nsTxt)
                            Text("\(network) · \(place)").font(.caption).foregroundStyle(Color.nsFaint)
                        }
                        Spacer()
                    }
                    Text(.init(lead)).font(.subheadline).foregroundStyle(Color.nsTxt)

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(bullets, id: \.self) { bullet($0) }
                    }
                    .padding(16)
                    .background(Color.nsSurface2, in: RoundedRectangle(cornerRadius: 14))

                    Text("Your choice is remembered. You can read the full details any time in Settings → Privacy Policy.")
                        .font(.caption2).foregroundStyle(Color.nsFaint)
                }
                .padding(20)
            }
            VStack(spacing: 10) {
                Button(action: onAgree) {
                    Text("Agree & run test")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .foregroundStyle(Color(hex: 0x04122e))
                        .background(Color.nsAccent, in: Capsule())
                }
                Button(action: onCancel) {
                    Text("Cancel").font(.subheadline.weight(.medium)).foregroundStyle(Color.nsMuted)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                }
            }
            .padding(20)
        }
        .background(Color.nsBg.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }

    private func bullet(_ markdown: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(Color.nsAccent).padding(.top, 7)
            Text(.init(markdown)).font(.subheadline).foregroundStyle(Color.nsTxt)
        }
    }
}
