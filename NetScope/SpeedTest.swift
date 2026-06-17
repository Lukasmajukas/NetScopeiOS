import SwiftUI
import Observation
import UniformTypeIdentifiers
#if canImport(CFNetwork)
import CFNetwork
#endif

// MARK: - Model & persistence

struct SpeedResult: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    var downloadMbps: Double
    var uploadMbps: Double
    var pingMs: Double
    var jitterMs: Double
    var network: String      // "Wi-Fi" / "Cellular" / "Wired"
    var ssid: String
    var isp: String
    var ip: String           // public (external) IP
    var server: String       // display label, e.g. "Cloudflare Newark, NJ"

    // Extra fields for the Ookla-style export. All optional so history saved
    // by older builds (which lacked them) still decodes cleanly.
    var connType: String?    // "Wi-Fi" / "Ethernet" / "5G" / "LTE" / "3G" / "2G"
    var lat: Double?
    var lon: Double?
    var downloadBytes: Int?  // total bytes pulled during the download phase
    var uploadBytes: Int?    // total bytes pushed during the upload phase
    var localIP: String?     // internal IP (en0 on Wi-Fi, pdp_ip0 on cellular)
    var serverCity: String?  // test server city, e.g. "Newark, NJ"
    var isVPN: Bool?
}

@MainActor
@Observable
final class HistoryStore {
    private(set) var items: [SpeedResult] = []
    /// Located results imported from external CSVs — kept separate from real test
    /// history so the history list stays clean, but folded into the coverage map.
    private(set) var importedResults: [SpeedResult] = []

    @ObservationIgnored private let url: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("speedtest-history.json")
    }()
    @ObservationIgnored private let importedURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("imported-coverage.json")
    }()

    // Cache the exported CSV so SwiftUI re-renders don't rewrite it to disk
    // on every frame; invalidated whenever the history changes.
    @ObservationIgnored private var csvCache: URL?
    @ObservationIgnored private var csvDirty = true
    @ObservationIgnored private var csvStamp = ""   // yyyyMMdd the cached file was named with

    /// Every located result that should appear on the coverage map.
    var coverageResults: [SpeedResult] { items + importedResults }

    init() { load() }

    func load() {
        if let data = try? Data(contentsOf: url),
           let rows = try? JSONDecoder().decode([SpeedResult].self, from: data) {
            items = rows.sorted { $0.date > $1.date }
            csvDirty = true
        }
        if let data = try? Data(contentsOf: importedURL),
           let rows = try? JSONDecoder().decode([SpeedResult].self, from: data) {
            importedResults = rows
        }
    }

    func add(_ r: SpeedResult) {
        items.insert(r, at: 0)                 // newest first, no cap
        csvDirty = true
        try? JSONEncoder().encode(items).write(to: url, options: .atomic)
    }

    func clear() {
        items = []
        csvDirty = true
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: CSV import (fills the coverage map from external exports)

    /// Imports located rows from a CSV at `url` (our Ookla-format export or a real
    /// Ookla Speedtest export). Returns the number of located rows added.
    @discardableResult
    func importCSV(from fileURL: URL) -> Int {
        let scoped = fileURL.startAccessingSecurityScopedResource()
        defer { if scoped { fileURL.stopAccessingSecurityScopedResource() } }
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return 0 }
        let rows = CSVImport.parse(text)
        guard !rows.isEmpty else { return 0 }
        importedResults.append(contentsOf: rows)
        try? JSONEncoder().encode(importedResults).write(to: importedURL, options: .atomic)
        return rows.count
    }

    func clearImported() {
        importedResults = []
        try? FileManager.default.removeItem(at: importedURL)
    }

    /// Writes the full history to a temp CSV file and returns it for sharing,
    /// matching the column layout of an Ookla Speedtest export (Download/Upload
    /// are kbps; DownloadBytes/UploadBytes are totals; ServerName and the IPs
    /// are always quoted). Regenerates only when the history changes.
    func csvFileURL() -> URL? {
        let stampFmt = DateFormatter()
        stampFmt.locale = Locale(identifier: "en_US_POSIX")
        stampFmt.dateFormat = "yyyyMMdd"
        let today = stampFmt.string(from: Date())

        // Reuse the cached file only if it's still current (same day) and present
        // on disk (temporaryDirectory can be purged by the OS).
        if !csvDirty, csvStamp == today, let cached = csvCache,
           FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd HH:mm"

        var s = "Date,ConnType,Lat,Lon,Download,DownloadBytes,Upload,UploadBytes,Latency,ServerName,InternalIp,ExternalIp,Is SpeedTest VPN\n"
        for r in items {
            let lat = r.lat.map { String(format: "%.6f", $0) } ?? ""
            let lon = r.lon.map { String(format: "%.6f", $0) } ?? ""
            let dlKbps = Int((max(0, r.downloadMbps) * 1000).rounded())   // Mbps → kbps
            let ulKbps = Int((max(0, r.uploadMbps) * 1000).rounded())
            let fields: [String] = [
                df.string(from: r.date),
                r.connType ?? r.network,
                lat, lon,
                String(dlKbps), String(r.downloadBytes ?? 0),
                String(ulKbps), String(r.uploadBytes ?? 0),
                String(Int(max(0, r.pingMs).rounded())),
                quote(r.serverCity ?? r.server),
                quote(r.localIP ?? ""),
                quote(r.ip),
                (r.isVPN ?? false) ? "Yes" : "No"
            ]
            s += fields.joined(separator: ",") + "\n"
        }

        let name = "SpeedTestExport_\(today).csv"
        let out = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        guard let data = s.data(using: .utf8), (try? data.write(to: out, options: .atomic)) != nil
        else { return nil }
        csvCache = out
        csvStamp = today
        csvDirty = false
        return out
    }

    /// Always wraps a field in quotes and escapes embedded quotes — used for the
    /// free-text columns (ServerName, IPs) to mirror the Ookla export exactly.
    private func quote(_ v: String) -> String {
        "\"\(v.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

// MARK: - ISP / server lookup

struct ISPInfo {
    var isp = ""
    var asn = ""
    var ip = ""
    var server = "Cloudflare"
    var colo = ""
    var serverCity = ""        // resolved colo city, e.g. "Newark, NJ" (for export)
}

// MARK: - Speed test engine
//
// Uses a delegate-based URLSession so download/upload throughput is sampled
// live (didReceive / didSendBodyData) across several concurrent streams — the
// efficient, "optimised" approach, mirroring the macOS version.

@MainActor
@Observable
final class SpeedTestEngine: NSObject {
    enum Phase: String { case idle, latency, downloading, uploading, done, failed }

    var phase: Phase = .idle
    var live: Double = 0        // current Mbps (running average)
    var progress: Double = 0    // 0…1 within the active phase
    var scaleMax: Double = 100  // gauge full-scale
    var download = 0.0
    var upload = 0.0
    var ping = 0.0
    var jitter = 0.0
    var info = ISPInfo()
    var running = false

    private let host = "speed.cloudflare.com"
    private let streams = 4
    private let downSeconds = 8.0
    private let upSeconds = 7.0

    // Cloudflare 403s non-browser requests — present a full browser header set.
    private let headers: [String: String] = [
        "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) " +
                      "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
        "Accept": "*/*",
        "Accept-Language": "en-US,en;q=0.9",
        "Referer": "https://speed.cloudflare.com/",
        "Origin": "https://speed.cloudflare.com"
    ]

    private let counter = ByteCounter()          // steady-state window (reset after warm-up)
    private let phaseCounter = ByteCounter()     // whole-phase total bytes (for the export)
    @ObservationIgnored private var dlActive = false
    @ObservationIgnored private var ulActive = false
    @ObservationIgnored private var liveTasks: [URLSessionTask] = []
    private let uploadBody = Data(count: 4 << 20)   // 4 MB per POST — fewer relaunches, steadier saturation

    // Context captured at the start of a run, written into the saved result.
    @ObservationIgnored private var ctx = RunContext()
    @ObservationIgnored private var dlBytes = 0
    @ObservationIgnored private var ulBytes = 0

    struct RunContext {
        var network = ""
        var ssid = ""
        var connType = ""
        var localIP = ""
        var lat: Double?
        var lon: Double?
    }

    private let control: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 8        // don't let ping/ISP hang on a stalled link
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()
    @ObservationIgnored private lazy var stream: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.timeoutIntervalForRequest = 30
        cfg.waitsForConnectivity = false
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1               // serial → no locks needed
        return URLSession(configuration: cfg, delegate: self, delegateQueue: q)
    }()

    func request(_ path: String) -> URLRequest {
        var r = URLRequest(url: URL(string: "https://\(host)\(path)")!)
        for (k, v) in headers { r.setValue(v, forHTTPHeaderField: k) }
        return r
    }

    // MARK: run

    func start(_ context: RunContext) {
        guard !running else { return }
        ctx = context
        running = true
        Task { await run() }
    }

    private func run() async {
        phase = .latency; live = 0; progress = 0; scaleMax = 100
        download = 0; upload = 0; ping = 0; jitter = 0
        dlBytes = 0; ulBytes = 0

        info = await fetchISP()

        let (p, j) = await measurePing()
        ping = p; jitter = j

        phase = .downloading
        download = await measure(.download, seconds: downSeconds)
        dlBytes = phaseCounter.value

        phase = .uploading
        upload = await measure(.upload, seconds: upSeconds)
        ulBytes = phaseCounter.value

        phase = .done
        live = 0; progress = 0

        let result = SpeedResult(downloadMbps: round1(download), uploadMbps: round1(upload),
                                 pingMs: round1(ping), jitterMs: round1(jitter),
                                 network: ctx.network, ssid: ctx.ssid,
                                 isp: info.isp, ip: info.ip, server: info.server,
                                 connType: ctx.connType.isEmpty ? ctx.network : ctx.connType,
                                 lat: ctx.lat, lon: ctx.lon,
                                 downloadBytes: dlBytes, uploadBytes: ulBytes,
                                 localIP: ctx.localIP,
                                 serverCity: info.serverCity.isEmpty ? info.server : info.serverCity,
                                 isVPN: isVPNActive())
        onFinished?(result)
        running = false
    }

    /// Set by the view so a completed run can be stored in history.
    @ObservationIgnored var onFinished: ((SpeedResult) -> Void)?

    // MARK: phases

    private enum Dir { case download, upload }

    // Steady-state throughput: let the streams ramp through TCP/TLS slow-start
    // for a short warm-up, then reset the counter and measure only the steady
    // window — the same way Ookla/Cloudflare avoid under-reporting fast links.
    private func measure(_ dir: Dir, seconds: Double) async -> Double {
        counter.reset()
        phaseCounter.reset()                        // total bytes for the whole phase (export)
        live = 0; progress = 0
        scaleMax = 100                              // rescale each phase so upload isn't dwarfed by a fast download
        startStreams(dir)

        let t0 = Date()
        let warmup = min(1.5, seconds * 0.25)
        var steadyStart: Date? = nil

        while Date().timeIntervalSince(t0) < seconds {
            try? await Task.sleep(nanoseconds: 200_000_000)
            let t = Date()
            if steadyStart == nil, t.timeIntervalSince(t0) >= warmup {
                counter.reset()                     // discard slow-start bytes
                steadyStart = t
            }
            let base = steadyStart ?? t0
            let span = max(0.001, t.timeIntervalSince(base))
            let avg = Double(counter.value) * 8 / span / 1e6
            live = avg
            if avg > scaleMax { scaleMax = niceMax(avg) }
            if let steadyStart {
                progress = min(1, t.timeIntervalSince(steadyStart) / max(0.001, seconds - warmup))
            } else {
                progress = min(0.2, t.timeIntervalSince(t0) / warmup * 0.2)
            }
        }
        stopStreams()
        let base = steadyStart ?? t0
        let span = max(0.001, Date().timeIntervalSince(base))
        return Double(counter.value) * 8 / span / 1e6
    }

    private func startStreams(_ dir: Dir) {
        if dir == .download { dlActive = true } else { ulActive = true }
        for _ in 0..<streams { launch(dir) }
    }

    private func launch(_ dir: Dir) {
        let task: URLSessionTask
        switch dir {
        case .download:
            task = stream.dataTask(with: request("/__down?bytes=100000000"))
        case .upload:
            var req = request("/__up")
            req.httpMethod = "POST"
            req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            task = stream.uploadTask(with: req, from: uploadBody)
        }
        // Tag the task with its direction so a stale completion can't relaunch
        // into the wrong phase (a cancelled download must not spawn an upload).
        task.taskDescription = (dir == .download) ? "download" : "upload"
        liveTasks.append(task)
        task.resume()
    }

    private func stopStreams() {
        dlActive = false; ulActive = false
        liveTasks.forEach { $0.cancel() }
        liveTasks.removeAll()
    }

    // MARK: ping + ISP (plain session, no delegate)

    private func measurePing(samples: Int = 7) async -> (Double, Double) {
        var times: [Double] = []
        for i in 0...samples {
            let t0 = Date()
            _ = try? await control.data(for: request("/__down?bytes=0"))
            if i > 0 { times.append(Date().timeIntervalSince(t0) * 1000) }
        }
        guard times.count > 1 else { return (times.first ?? 0, 0) }
        // ping = best (minimum) RTT; jitter = mean absolute difference between
        // consecutive samples (RFC 3550), which tracks instability better than stdev.
        let minRtt = times.min() ?? 0
        var diffSum = 0.0
        for k in 1..<times.count { diffSum += abs(times[k] - times[k - 1]) }
        return (minRtt, diffSum / Double(times.count - 1))
    }

    private func fetchISP() async -> ISPInfo {
        var out = ISPInfo()
        // cdn-cgi/trace → public IP + colo
        if let (d, _) = try? await control.data(for: request("/cdn-cgi/trace")),
           let txt = String(data: d, encoding: .utf8) {
            var kv: [String: String] = [:]
            for line in txt.split(separator: "\n") {
                let p = line.split(separator: "=", maxSplits: 1)
                if p.count == 2 { kv[String(p[0])] = String(p[1]) }
            }
            out.ip = kv["ip"] ?? ""
            out.colo = kv["colo"] ?? ""
            out.serverCity = coloCity[out.colo] ?? out.colo
            out.server = out.serverCity.isEmpty ? "Cloudflare" : "Cloudflare \(out.serverCity)"
        }
        // ipinfo.io → ISP / ASN
        if let url = URL(string: "https://ipinfo.io/json"),
           let (d, _) = try? await control.data(from: url),
           let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            let org = (j["org"] as? String) ?? ""
            if let r = org.range(of: #"^AS(\d+)\s+"#, options: .regularExpression) {
                out.asn = String(org[r].dropFirst(2).trimmingCharacters(in: .whitespaces))
                out.isp = String(org[r.upperBound...])
            } else {
                out.isp = org
            }
            if out.isp.isEmpty { out.isp = (j["org"] as? String) ?? "" }
        }
        return out
    }

    private func round1(_ v: Double) -> Double { (v * 10).rounded() / 10 }
}

// URLSession delegate: count bytes live, and keep streams full for the window.
extension SpeedTestEngine: URLSessionDataDelegate, URLSessionTaskDelegate {
    nonisolated func urlSession(_ s: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        counter.add(data.count)
        phaseCounter.add(data.count)
    }
    nonisolated func urlSession(_ s: URLSession, task: URLSessionTask,
                                didSendBodyData bytesSent: Int64, totalBytesSent: Int64,
                                totalBytesExpectedToSend: Int64) {
        counter.add(Int(bytesSent))
        phaseCounter.add(Int(bytesSent))
    }
    nonisolated func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let dir = task.taskDescription ?? ""    // captured on the delegate queue
        Task { @MainActor in
            // A stream finished (or was cancelled) — relaunch to keep the pipe full,
            // but ONLY for the same direction that's still active. This stops a
            // download cancellation, whose MainActor hop lands after the upload
            // phase has begun, from spawning extra upload streams.
            switch dir {
            case "download": if dlActive { launch(.download) }
            case "upload":   if ulActive { launch(.upload) }
            default: break
            }
        }
    }
}

/// Thread-safe byte counter (written on the serial delegate queue, read on main).
final class ByteCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var total = 0
    func add(_ n: Int) { lock.lock(); total += n; lock.unlock() }
    func reset() { lock.lock(); total = 0; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return total }
}

func niceMax(_ v: Double) -> Double {
    for s in [25.0, 50, 100, 150, 250, 500, 750, 1000, 1500, 2500, 5000, 10000] where v <= s * 0.92 { return s }
    return (v / 1000).rounded(.up) * 1000
}

/// Best-effort VPN detection: a VPN adds a scoped tunnel interface
/// (utun/tap/tun/ppp/ipsec) to the system proxy settings. Mirrors the
/// "Is SpeedTest VPN" column in the Ookla export.
func isVPNActive() -> Bool {
    guard let cf = CFNetworkCopySystemProxySettings()?.takeRetainedValue() else { return false }
    guard let scoped = (cf as NSDictionary)["__SCOPED__"] as? [String: Any] else { return false }
    let vpnPrefixes = ["tap", "tun", "ppp", "ipsec", "utun"]
    return scoped.keys.contains { key in
        let k = key.lowercased()
        return vpnPrefixes.contains { k.hasPrefix($0) }
    }
}

let coloCity: [String: String] = [
    "EWR": "Newark, NJ", "JFK": "New York, NY", "BOS": "Boston, MA", "IAD": "Washington, DC",
    "ATL": "Atlanta, GA", "ORD": "Chicago, IL", "DFW": "Dallas, TX", "DEN": "Denver, CO",
    "LAX": "Los Angeles, CA", "SJC": "San Jose, CA", "SEA": "Seattle, WA", "MIA": "Miami, FL",
    "YYZ": "Toronto", "LHR": "London", "CDG": "Paris", "FRA": "Frankfurt", "AMS": "Amsterdam",
    "NRT": "Tokyo", "SIN": "Singapore", "SYD": "Sydney", "GRU": "São Paulo"
]

// MARK: - CSV import (the inverse of HistoryStore.csvFileURL)
//
// Parses an Ookla-format CSV — our own export or a real Speedtest export — into
// located results for the coverage map. Header-driven and case-insensitive, so
// column order/spacing doesn't matter; rows without a usable lat/lon are skipped.

enum CSVImport {
    static func parse(_ text: String) -> [SpeedResult] {
        let lines = splitLines(text)
        guard lines.count > 1 else { return [] }
        let header = parseLine(lines[0]).map(normalize)

        func idx(_ names: [String]) -> Int? {
            for n in names { if let i = header.firstIndex(of: n) { return i } }
            return nil
        }
        let iLat  = idx(["lat", "latitude"])
        let iLon  = idx(["lon", "long", "longitude"])
        let iDown = idx(["download", "downloadkbps", "downloadmbps"])
        let iUp   = idx(["upload", "uploadkbps", "uploadmbps"])
        let iPing = idx(["latency", "ping", "latencyms"])
        let iDate = idx(["date", "timestamp", "time"])
        let iSrv  = idx(["servername", "server"])
        guard let iLat, let iLon else { return [] }   // can't map a row with no location

        // Ookla Download/Upload are kbps; a column explicitly named *mbps is not.
        let downIsMbps = (iDown.map { header[$0].contains("mbps") }) ?? false
        let upIsMbps   = (iUp.map   { header[$0].contains("mbps") }) ?? false

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd HH:mm"

        var out: [SpeedResult] = []
        for raw in lines.dropFirst() {
            let f = parseLine(raw)
            guard !f.isEmpty else { continue }
            func v(_ i: Int?) -> String { (i.flatMap { $0 < f.count ? f[$0] : nil }) ?? "" }

            guard let lat = Double(v(iLat)), let lon = Double(v(iLon)),
                  abs(lat) <= 90, abs(lon) <= 180, !(lat == 0 && lon == 0) else { continue }

            let down = speed(v(iDown), alreadyMbps: downIsMbps)
            let up   = speed(v(iUp),   alreadyMbps: upIsMbps)
            guard down > 0 else { continue }            // a tile needs a download value
            let ping = Double(v(iPing).filter { $0.isNumber || $0 == "." }) ?? 0
            let date = df.date(from: v(iDate)) ?? Date()
            let srv  = v(iSrv)

            out.append(SpeedResult(
                date: date, downloadMbps: down, uploadMbps: up, pingMs: ping, jitterMs: 0,
                network: "Imported", ssid: "", isp: "Imported", ip: "",
                server: srv.isEmpty ? "Imported" : srv,
                connType: "Imported", lat: lat, lon: lon,
                downloadBytes: nil, uploadBytes: nil, localIP: nil,
                serverCity: srv.isEmpty ? nil : srv, isVPN: nil))
        }
        return out
    }

    private static func speed(_ s: String, alreadyMbps: Bool) -> Double {
        guard let v = Double(s.trimmingCharacters(in: .whitespaces)), v > 0 else { return 0 }
        return alreadyMbps ? v : v / 1000              // kbps → Mbps
    }

    private static func normalize(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespaces).lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
    }

    private static func splitLines(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
    }

    /// Quote-aware field split for one CSV line ("" escapes a quote inside a field).
    private static func parseLine(_ line: String) -> [String] {
        var fields: [String] = []
        var cur = ""
        var inQuotes = false
        var i = line.startIndex
        while i < line.endIndex {
            let c = line[i]
            if inQuotes {
                if c == "\"" {
                    let next = line.index(after: i)
                    if next < line.endIndex, line[next] == "\"" { cur.append("\""); i = next }
                    else { inQuotes = false }
                } else { cur.append(c) }
            } else if c == "\"" {
                inQuotes = true
            } else if c == "," {
                fields.append(cur); cur = ""
            } else {
                cur.append(c)
            }
            i = line.index(after: i)
        }
        fields.append(cur)
        return fields.map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
