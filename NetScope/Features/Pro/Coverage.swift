import SwiftUI
import Observation
import MapKit
import UniformTypeIdentifiers

// MARK: - Speed coverage tiles
//
// Pro feature. Every saved speed test already carries lat/lon, so we bin those
// points into a fixed-degree grid and colour each tile by its average download
// speed — a personal coverage heatmap. Tiles are Codable so they can be merged
// with a shared set synced from a Mac "backbone" (see CoverageSync below).

struct SpeedTile: Identifiable, Codable, Equatable {
    var key: String        // "gx:gy" grid cell id
    var lat: Double        // tile centre
    var lon: Double
    var grid: Double       // tile size in degrees
    var down: Double       // average download Mbps
    var up: Double         // average upload Mbps
    var count: Int         // tests in this cell
    var id: String { key }
}

enum Coverage {
    /// ~280 m cells at the equator. Coarse enough that a handful of tests in a
    /// neighbourhood form a readable patch, fine enough to tell streets apart.
    static let defaultGrid = 0.0025

    /// Bin results with a location into average-speed tiles.
    static func tiles(from results: [SpeedResult], grid: Double = defaultGrid) -> [SpeedTile] {
        var acc: [String: (d: Double, u: Double, n: Int)] = [:]
        for r in results {
            guard let lat = r.lat, let lon = r.lon, r.downloadMbps > 0 else { continue }
            let gx = Int((lat / grid).rounded(.down))
            let gy = Int((lon / grid).rounded(.down))
            let key = "\(gx):\(gy)"
            var e = acc[key] ?? (0, 0, 0)
            e.d += r.downloadMbps
            e.u += max(0, r.uploadMbps)
            e.n += 1
            acc[key] = e
        }
        return acc.map { key, e in
            let parts = key.split(separator: ":")
            let gx = Double(parts[0]) ?? 0
            let gy = Double(parts[1]) ?? 0
            return SpeedTile(key: key,
                             lat: (gx + 0.5) * grid,
                             lon: (gy + 0.5) * grid,
                             grid: grid,
                             down: e.d / Double(e.n),
                             up: e.u / Double(e.n),
                             count: e.n)
        }
    }

    /// Merge two tile sets (e.g. local + Mac-synced), count-weighting overlaps.
    static func merge(_ a: [SpeedTile], _ b: [SpeedTile]) -> [SpeedTile] {
        var byKey: [String: SpeedTile] = [:]
        for t in a + b {
            if var ex = byKey[t.key] {
                let n = ex.count + t.count
                guard n > 0 else { continue }
                ex.down = (ex.down * Double(ex.count) + t.down * Double(t.count)) / Double(n)
                ex.up = (ex.up * Double(ex.count) + t.up * Double(t.count)) / Double(n)
                ex.count = n
                byKey[t.key] = ex
            } else {
                byKey[t.key] = t
            }
        }
        return Array(byKey.values)
    }
}

// MARK: - Speed → colour scale (shared by the map and the legend)

struct SpeedBand {
    let upTo: Double      // upper bound (Mbps); .infinity for the top band
    let hex: UInt
    let label: String
}

let speedBands: [SpeedBand] = [
    .init(upTo: 25,        hex: 0xff5252, label: "< 25"),
    .init(upTo: 100,       hex: 0xffa726, label: "25–100"),
    .init(upTo: 300,       hex: 0xffe14d, label: "100–300"),
    .init(upTo: 1000,      hex: 0x37d67a, label: "300–1000"),
    .init(upTo: .infinity, hex: 0x2ee6c8, label: "1 Gbps +"),
]

/// Hard-bucket colour for the legend swatches.
func speedHex(_ mbps: Double) -> UInt {
    for b in speedBands where mbps < b.upTo { return b.hex }
    return speedBands.last!.hex
}

// MARK: - Continuous tile colour + geometry (for the native Map heatmap)

/// Smoothly interpolated tile colour across the speed ramp, so neighbouring
/// tiles blend instead of snapping between five buckets.
func tileColor(_ mbps: Double) -> Color {
    // (speed Mbps, RGB) anchors spanning the ramp.
    let stops: [(Double, Double, Double, Double)] = [
        (0,    1.00, 0.32, 0.32),   // red
        (60,   1.00, 0.65, 0.15),   // orange
        (200,  1.00, 0.88, 0.30),   // yellow
        (650,  0.22, 0.84, 0.48),   // green
        (1200, 0.18, 0.90, 0.78),   // teal
    ]
    let v = max(0, mbps)
    if v <= stops.first!.0 { let s = stops.first!; return Color(.sRGB, red: s.1, green: s.2, blue: s.3) }
    if v >= stops.last!.0  { let s = stops.last!;  return Color(.sRGB, red: s.1, green: s.2, blue: s.3) }
    for i in 1..<stops.count where v <= stops[i].0 {
        let a = stops[i - 1], b = stops[i]
        let f = (v - a.0) / (b.0 - a.0)
        return Color(.sRGB,
                     red:   a.1 + (b.1 - a.1) * f,
                     green: a.2 + (b.2 - a.2) * f,
                     blue:  a.3 + (b.3 - a.3) * f)
    }
    let s = stops.last!; return Color(.sRGB, red: s.1, green: s.2, blue: s.3)
}

/// Square corners of a tile's grid cell.
func tileCorners(_ t: SpeedTile) -> [CLLocationCoordinate2D] {
    let half = t.grid / 2
    return [
        .init(latitude: t.lat - half, longitude: t.lon - half),
        .init(latitude: t.lat - half, longitude: t.lon + half),
        .init(latitude: t.lat + half, longitude: t.lon + half),
        .init(latitude: t.lat + half, longitude: t.lon - half),
    ]
}

/// Region that frames all tiles, with padding.
func coverageRegion(for tiles: [SpeedTile]) -> MKCoordinateRegion {
    let lats = tiles.map(\.lat), lons = tiles.map(\.lon)
    let minLat = lats.min() ?? 0, maxLat = lats.max() ?? 0
    let minLon = lons.min() ?? 0, maxLon = lons.max() ?? 0
    return MKCoordinateRegion(
        center: .init(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
        span: MKCoordinateSpan(latitudeDelta: max(0.01, (maxLat - minLat) * 1.6),
                               longitudeDelta: max(0.01, (maxLon - minLon) * 1.6)))
}

// MARK: - Mac "backbone" sync
//
// Optional. Point this at a Mac running the NetScope coverage endpoint and the
// app POSTs its local tiles and gets back the merged set aggregated across every
// device that reports in — turning one Mac into a shared coverage backbone.
//
// Contract (JSON over HTTP):
//   POST <base>/coverage   body: {"tiles":[SpeedTile…]}   ->  {"tiles":[merged…]}
// Any failure is non-fatal: the map keeps showing local tiles.

@MainActor
@Observable
final class CoverageSync {
    var status = ""
    var syncing = false

    private struct Payload: Codable { var tiles: [SpeedTile] }

    func sync(base urlString: String, local: [SpeedTile]) async -> [SpeedTile] {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { status = "No Mac server configured"; return local }
        guard let url = URL(string: trimmed.hasSuffix("/coverage")
                            ? trimmed : trimmed + "/coverage") else {
            status = "Invalid server URL"; return local
        }
        syncing = true
        defer { syncing = false }
        do {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.timeoutInterval = 8
            req.httpBody = try JSONEncoder().encode(Payload(tiles: local))

            let cfg = URLSessionConfiguration.ephemeral
            cfg.waitsForConnectivity = false
            let (data, resp) = try await URLSession(configuration: cfg).data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                status = "Mac server error"; return local
            }
            let merged = try JSONDecoder().decode(Payload.self, from: data).tiles
            // The Mac server is user-supplied and untrusted: drop tiles with
            // non-finite speeds (NaN/∞ would trap Int(...) in the renderer/stats)
            // or out-of-range coordinates before merging.
            let clean = merged.filter {
                $0.down.isFinite && $0.up.isFinite && $0.count > 0
                    && abs($0.lat) <= 90 && abs($0.lon) <= 180
            }
            status = "Synced \(clean.count) tiles from Mac"
            return Coverage.merge(local, clean)
        } catch {
            status = "Couldn't reach Mac — showing local only"
            return local
        }
    }
}

// MARK: - Coverage map screen

struct CoverageMapView: View {
    @Environment(HistoryStore.self) private var history
    @State private var sync = CoverageSync()
    @AppStorage("macSyncURL") private var macURL = ""

    @State private var tiles: [SpeedTile] = []
    @State private var camera: MapCameraPosition = .automatic
    @State private var didFit = false
    @State private var selected: SpeedTile?
    @State private var showMacField = false
    @State private var showImporter = false
    @State private var importMessage = ""

    // Rendered as a plain scaffold (not `Screen`) because this view is pushed via
    // NavigationLink — wrapping it in another NavigationStack would nest stacks and
    // double the nav bar. It relies on the presenting Speed tab's NavigationStack.
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                mapCard
                if let t = selected { selectedCard(t) }
                legendCard
                statsCard
                importCard
                macCard
            }
            .padding(16)
        }
        .background(Color.nsBg.ignoresSafeArea())
        .navigationTitle("Coverage")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.nsBg, for: .navigationBar)
        #endif
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.commaSeparatedText, .plainText, .text]) { result in
            switch result {
            case .success(let url):
                let n = history.importCSV(from: url)
                importMessage = n > 0 ? "Imported \(n) located rows." : "No located rows found in that file."
                rebuild()
            case .failure(let e):
                importMessage = "Couldn't open that file: \(e.localizedDescription)"
            }
        }
        .onAppear(perform: rebuild)
        .onChange(of: history.coverageResults.count) { _, _ in rebuild() }
    }

    private var coverageTiles: [SpeedTile] { Coverage.tiles(from: history.coverageResults) }

    private func rebuild() {
        withAnimation(.smooth) { tiles = coverageTiles }
        if !tiles.isEmpty, !didFit {
            didFit = true
            camera = .region(coverageRegion(for: tiles))
        }
    }

    private func tile(at coord: CLLocationCoordinate2D) -> SpeedTile? {
        tiles.first {
            abs(coord.latitude - $0.lat) <= $0.grid / 2 &&
            abs(coord.longitude - $0.lon) <= $0.grid / 2
        }
    }

    // MARK: Map

    private var mapCard: some View {
        Card {
            if tiles.isEmpty {
                ContentUnavailableView {
                    Label("No located tests yet", systemImage: "map")
                } description: {
                    Text("Run a speed test with Location allowed — or import a CSV below — and it'll appear here as a coloured tile.")
                }
                .frame(maxWidth: .infinity).padding(.vertical, 18)
            } else {
                MapReader { proxy in
                    Map(position: $camera) {
                        ForEach(tiles) { t in
                            // Solid colour square per tile (one flat colour by speed),
                            // with a crisp matching edge.
                            MapPolygon(coordinates: tileCorners(t))
                                .foregroundStyle(tileColor(t.down))
                                .stroke(tileColor(t.down), lineWidth: 1)
                        }
                        UserAnnotation()
                    }
                    .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                    .onTapGesture { pt in
                        if let coord = proxy.convert(pt, from: .local) {
                            withAnimation(.snappy) { selected = tile(at: coord) }
                        }
                    }
                }
                .frame(height: 320)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.nsLine, lineWidth: 1))
                .transition(.opacity)
            }
        }
    }

    private func selectedCard(_ t: SpeedTile) -> some View {
        Card {
            HStack {
                Circle().fill(tileColor(t.down)).frame(width: 12, height: 12)
                Text("Selected tile").font(.subheadline.weight(.semibold)).foregroundStyle(Color.nsTxt)
                Spacer()
                Button { withAnimation(.snappy) { selected = nil } } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color.nsFaint)
                }
            }
            statRow("Avg download", "\(Int(t.down.rounded())) Mbps")
            statRow("Avg upload", "\(Int(t.up.rounded())) Mbps")
            statRow("Tests here", "\(t.count)")
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var legendCard: some View {
        Card("Download speed") {
            HStack(spacing: 0) {
                ForEach(speedBands.indices, id: \.self) { i in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(hex: speedBands[i].hex))
                            .frame(height: 10)
                        Text(speedBands[i].label)
                            .font(.system(size: 9)).foregroundStyle(Color.nsMuted)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 2)
                }
            }
            Text("Mbps · each tile is the average of every test that landed in it. Tap a tile for details.")
                .font(.caption2).foregroundStyle(Color.nsFaint)
        }
    }

    private var statsCard: some View {
        Card("Coverage") {
            statRow("Tiles mapped", "\(tiles.count)")
            statRow("Tests located", "\(history.coverageResults.filter { $0.lat != nil }.count)")
            if !history.importedResults.isEmpty {
                statRow("Imported", "\(history.importedResults.count)")
            }
            if let fastest = tiles.max(by: { $0.down < $1.down }) {
                statRow("Fastest tile", "\(Int(fastest.down.rounded())) Mbps")
            }
            if let busiest = tiles.max(by: { $0.count < $1.count }) {
                statRow("Most-tested tile", "\(busiest.count) tests")
            }
        }
    }

    // MARK: Import

    private var importCard: some View {
        Card("Add data") {
            Text("Import an Ookla-format CSV — this app's export or a real Speedtest export — to drop its located results onto the map.")
                .font(.caption).foregroundStyle(Color.nsMuted)
            HStack(spacing: 12) {
                Button { showImporter = true } label: {
                    Label("Import CSV", systemImage: "square.and.arrow.down")
                        .font(.caption.weight(.semibold)).foregroundStyle(Color.nsAccent)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .nsGlassCapsule()
                }
                if !history.importedResults.isEmpty {
                    Button(role: .destructive) {
                        history.clearImported(); importMessage = ""; rebuild()
                    } label: {
                        Label("Clear imported", systemImage: "trash")
                            .font(.caption.weight(.semibold)).foregroundStyle(Color(hex: 0xff6b6b))
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .nsGlassCapsule(tinted: false)
                    }
                }
                Spacer()
            }
            if !importMessage.isEmpty {
                Text(importMessage).font(.caption2).foregroundStyle(Color.nsFaint)
            }
        }
    }

    // MARK: Mac backbone

    private var macCard: some View {
        Card("Mac backbone") {
            Text("Optional: aggregate tiles across devices through a Mac running NetScope. Your phone POSTs its tiles and gets back the merged coverage from everyone reporting in.")
                .font(.caption).foregroundStyle(Color.nsMuted)

            if showMacField || !macURL.isEmpty {
                TextField("http://your-mac.local:8765", text: $macURL)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.caption)
            }

            HStack(spacing: 12) {
                Button {
                    showMacField = true
                    Task { tiles = await sync.sync(base: macURL, local: coverageTiles) }
                } label: {
                    HStack(spacing: 6) {
                        if sync.syncing { ProgressView().controlSize(.small) }
                        Label("Sync with Mac", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(Color.nsAccent)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .nsGlassCapsule()
                }
                .disabled(sync.syncing)
                Spacer()
            }
            if !sync.status.isEmpty {
                Text(sync.status).font(.caption2).foregroundStyle(Color.nsFaint)
            }
        }
    }

    private func statRow(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).foregroundStyle(Color.nsMuted)
            Spacer()
            Text(v).foregroundStyle(Color.nsTxt).monospacedDigit()
                .contentTransition(.numericText())
        }
        .font(.subheadline)
        .padding(.vertical, 5)
        .overlay(alignment: .bottom) { Divider().overlay(Color.nsLine) }
    }
}
