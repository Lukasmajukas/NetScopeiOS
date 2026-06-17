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
    @Environment(HistoryStore.self) private var history
    @Environment(ConnectionMonitor.self) private var connection
    @Environment(LocationProvider.self) private var location
    @Environment(ProManager.self) private var pro
    @State private var showSettings = false

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
                runButton
            }
            trendCard
            historyCard
            coverageCard
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(history)
                .environment(location)
                .environment(pro)
        }
        .onAppear {
            engine.onFinished = { history.add($0) }
            location.start()   // warm up location so a finished test can record lat/lon
            // Optional: auto-start a test on launch (Shortcuts/automation, or `-autorun 1`).
            if UserDefaults.standard.bool(forKey: "autorun") {
                Task {
                    try? await Task.sleep(nanoseconds: 600_000_000)   // let the path monitor settle
                    if !engine.running { engine.start(runContext()) }
                }
            }
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

    private var runButton: some View {
        Button {
            engine.start(runContext())
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
