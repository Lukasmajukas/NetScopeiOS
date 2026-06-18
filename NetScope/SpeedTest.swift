import SwiftUI
import Observation
import UniformTypeIdentifiers
import Network
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
    // The server/location this run tests against (chosen in the picker).
    @ObservationIgnored private var server: SpeedServer = .cloudflare

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

    // WebSocket session for the M-Lab / NDT7 backbone. No delegate — we drive it
    // with the receive/send completion-handler API, so completions land on the
    // session's own background queue (counters/throughput holders are lock-guarded).
    @ObservationIgnored private lazy var wsSession: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 12       // WebSocket handshake timeout
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()

    func request(_ path: String) -> URLRequest {
        var r = URLRequest(url: URL(string: "https://\(host)\(path)")!)
        for (k, v) in headers { r.setValue(v, forHTTPHeaderField: k) }
        return r
    }

    // MARK: run

    func start(_ context: RunContext, server: SpeedServer = .cloudflare) {
        guard !running else { return }
        ctx = context
        self.server = server
        running = true
        Task { await run() }
    }

    private func run() async {
        phase = .latency; live = 0; progress = 0; scaleMax = 100
        download = 0; upload = 0; ping = 0; jitter = 0
        dlBytes = 0; ulBytes = 0

        let srv = server
        info = await fetchISP(for: srv)

        // Latency: Cloudflare uses a tiny HTTP round-trip; M-Lab uses a TCP-connect
        // RTT to the chosen machine (no public HTTP probe path there).
        switch srv.provider {
        case .cloudflare: (ping, jitter) = await measurePingHTTP()
        case .mlab:       (ping, jitter) = await measurePingTCP(host: srv.host)
        }

        phase = .downloading
        switch srv.provider {
        case .cloudflare:
            download = await measure(.download, seconds: downSeconds)
            dlBytes = phaseCounter.value
        case .mlab:
            (download, dlBytes) = await ndt7(.download, url: srv.downloadURL, seconds: downSeconds)
        }

        phase = .uploading
        switch srv.provider {
        case .cloudflare:
            upload = await measure(.upload, seconds: upSeconds)
            ulBytes = phaseCounter.value
        case .mlab:
            (upload, ulBytes) = await ndt7(.upload, url: srv.uploadURL, seconds: upSeconds)
        }

        // A run that moved zero bytes in both directions means we never reached
        // the server (offline, airplane mode, unreachable/expired M-Lab URL). Mark
        // it failed and DON'T persist a bogus 0/0/0 row to history or the CSV.
        if dlBytes == 0 && ulBytes == 0 {
            phase = .failed
            live = 0; progress = 0
            running = false
            return
        }

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

    private func measurePingHTTP(samples: Int = 7) async -> (Double, Double) {
        var times: [Double] = []
        for i in 0...samples {
            let t0 = Date()
            _ = try? await control.data(for: request("/__down?bytes=0"))
            if i > 0 { times.append(Date().timeIntervalSince(t0) * 1000) }
        }
        return Self.pingStats(times)
    }

    /// TCP-connect RTT to host:443 (used for M-Lab machines, which have no public
    /// HTTP probe path). ping = best sample; jitter = mean consecutive difference.
    private func measurePingTCP(host: String, samples: Int = 6) async -> (Double, Double) {
        var times: [Double] = []
        for _ in 0..<samples {
            if let ms = await NetLatency.connect(host: host, port: 443) { times.append(ms) }
        }
        return Self.pingStats(times)
    }

    /// ping = best (minimum) RTT; jitter = mean absolute difference between
    /// consecutive samples (RFC 3550), which tracks instability better than stdev.
    private static func pingStats(_ times: [Double]) -> (Double, Double) {
        guard times.count > 1 else { return (times.first ?? 0, 0) }
        let minRtt = times.min() ?? 0
        var diffSum = 0.0
        for k in 1..<times.count { diffSum += abs(times[k] - times[k - 1]) }
        return (minRtt, diffSum / Double(times.count - 1))
    }

    private func fetchISP(for server: SpeedServer) async -> ISPInfo {
        var out = ISPInfo()
        // ipinfo.io → public IP + ISP / ASN (provider-independent)
        if let url = URL(string: "https://ipinfo.io/json"),
           let (d, _) = try? await control.data(from: url),
           let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            out.ip = (j["ip"] as? String) ?? ""
            let org = (j["org"] as? String) ?? ""
            if let r = org.range(of: #"^AS(\d+)\s+"#, options: .regularExpression) {
                out.asn = String(org[r].dropFirst(2).trimmingCharacters(in: .whitespaces))
                out.isp = String(org[r.upperBound...])
            } else {
                out.isp = org
            }
        }
        switch server.provider {
        case .cloudflare:
            // cdn-cgi/trace → colo + authoritative public IP (overrides ipinfo's).
            if let (d, _) = try? await control.data(for: request("/cdn-cgi/trace")),
               let txt = String(data: d, encoding: .utf8) {
                var kv: [String: String] = [:]
                for line in txt.split(separator: "\n") {
                    let p = line.split(separator: "=", maxSplits: 1)
                    if p.count == 2 { kv[String(p[0])] = String(p[1]) }
                }
                if let ip = kv["ip"], !ip.isEmpty { out.ip = ip }
                out.colo = kv["colo"] ?? ""
                out.serverCity = coloCity[out.colo] ?? out.colo
                out.server = out.serverCity.isEmpty ? "Cloudflare" : "Cloudflare \(out.serverCity)"
            } else {
                out.server = "Cloudflare"
            }
        case .mlab:
            out.serverCity = server.country.isEmpty ? server.city : "\(server.city), \(server.country)"
            out.server = out.serverCity.isEmpty ? "M-Lab" : "M-Lab · \(out.serverCity)"
        }
        return out
    }

    // MARK: NDT7 (M-Lab) — WebSocket download/upload over a single TCP connection
    //
    // Download: the server streams binary messages; we count received bytes for
    // client-side goodput. Upload: we push fixed-size binary messages as fast as
    // backpressure allows, and prefer the server's own AppInfo measurement (bytes
    // it actually received) for the final figure, falling back to client-sent bytes.

    private func ndt7(_ dir: Dir, url: URL?, seconds: Double) async -> (Double, Int) {
        guard let url else { return (0, 0) }
        let task = wsSession.webSocketTask(with: url, protocols: ["net.measurementlab.ndt.v7"])
        let window = ByteCounter()        // steady-window bytes (after warm-up)
        let total  = ByteCounter()        // whole-phase bytes (for the export)
        let serverMbps = Locked<Double?>(nil)
        task.resume()

        if dir == .download {
            Self.pumpReceive(task, window: window, total: total, server: nil)
        } else {
            // Drain the server's measurement messages (authoritative throughput),
            // and pump uploads. 128 KB messages are within the ndt7 bounds and keep
            // a mobile uplink saturated without head-of-line blocking.
            Self.pumpReceive(task, window: nil, total: nil, server: serverMbps)
            Self.pumpSend(task, buf: Data(count: 1 << 17), window: window, total: total,
                          deadline: Date().addingTimeInterval(seconds))
        }

        live = 0; progress = 0; scaleMax = 100
        let t0 = Date()
        let warmup = min(2.0, seconds * 0.25)
        var steadyStart: Date? = nil
        window.reset()
        while Date().timeIntervalSince(t0) < seconds {
            try? await Task.sleep(nanoseconds: 200_000_000)
            let t = Date()
            if steadyStart == nil, t.timeIntervalSince(t0) >= warmup {
                window.reset(); steadyStart = t
            }
            let base = steadyStart ?? t0
            let span = max(0.001, t.timeIntervalSince(base))
            let avg = Double(window.value) * 8 / span / 1e6
            live = avg
            if avg > scaleMax { scaleMax = niceMax(avg) }
            if let steadyStart {
                progress = min(1, t.timeIntervalSince(steadyStart) / max(0.001, seconds - warmup))
            } else {
                progress = min(0.2, t.timeIntervalSince(t0) / warmup * 0.2)
            }
        }
        task.cancel(with: .goingAway, reason: nil)

        let base = steadyStart ?? t0
        let span = max(0.001, Date().timeIntervalSince(base))
        let clientMbps = Double(window.value) * 8 / span / 1e6
        // Upload: trust the server's received-byte count when it reported one.
        if dir == .upload, let s = serverMbps.value, s > 0 { return (s, total.value) }
        return (clientMbps, total.value)
    }

    /// Recursively re-arm a WebSocket receive on the session's background queue,
    /// counting bytes and (for uploads) parsing the server's goodput measurements.
    nonisolated private static func pumpReceive(_ task: URLSessionWebSocketTask,
                                                window: ByteCounter?, total: ByteCounter?,
                                                server: Locked<Double?>?) {
        task.receive { result in
            guard case .success(let msg) = result else { return }   // closed/cancelled → stop
            switch msg {
            case .data(let d):
                window?.add(d.count); total?.add(d.count)
            case .string(let s):
                window?.add(s.utf8.count); total?.add(s.utf8.count)
                if let server { parseMeasurement(s, into: server) }
            @unknown default: break
            }
            pumpReceive(task, window: window, total: total, server: server)
        }
    }

    /// Recursively send fixed-size binary frames until the deadline, one at a time
    /// so the completion handler provides natural backpressure.
    nonisolated private static func pumpSend(_ task: URLSessionWebSocketTask, buf: Data,
                                             window: ByteCounter, total: ByteCounter, deadline: Date) {
        guard Date() < deadline else { return }
        task.send(.data(buf)) { err in
            guard err == nil else { return }
            window.add(buf.count); total.add(buf.count)
            pumpSend(task, buf: buf, window: window, total: total, deadline: deadline)
        }
    }

    /// Parse an ndt7 JSON Measurement and store its goodput (Mbps). AppInfo is
    /// app-level (preferred); TCPInfo is the kernel's view. ElapsedTime is in µs.
    nonisolated private static func parseMeasurement(_ s: String, into box: Locked<Double?>) {
        guard let d = s.data(using: .utf8),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
        func mbps(_ obj: [String: Any], _ bytesKey: String) -> Double? {
            guard let n = (obj[bytesKey] as? NSNumber)?.doubleValue,
                  let e = (obj["ElapsedTime"] as? NSNumber)?.doubleValue, e > 0 else { return nil }
            return n * 8 / (e / 1e6) / 1e6
        }
        if let app = j["AppInfo"] as? [String: Any], let v = mbps(app, "NumBytes") {
            box.value = v
        } else if let tcp = j["TCPInfo"] as? [String: Any], let v = mbps(tcp, "BytesReceived") {
            box.value = v
        }
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

/// A tiny lock-guarded box so a value written on a background WebSocket callback
/// can be read safely from the main actor (used for the server's NDT7 goodput).
final class Locked<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var v: T
    init(_ value: T) { v = value }
    var value: T {
        get { lock.lock(); defer { lock.unlock() }; return v }
        set { lock.lock(); v = newValue; lock.unlock() }
    }
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

// MARK: - Speed-test servers / locations
//
// Two open backbones: Cloudflare (anycast — always the nearest edge, one entry)
// and M-Lab / NDT7 — an open-source internet measurement network. M-Lab's
// Locate API hands back several nearby machines by city, which become the
// selectable locations with per-server ping.

struct SpeedServer: Identifiable, Equatable, Sendable {
    enum Provider: String, Sendable { case cloudflare, mlab }

    let id: String
    let provider: Provider
    let city: String
    let country: String
    let host: String          // hostname used for the TCP-connect ping
    var downloadURL: URL?     // M-Lab: pre-signed wss download URL
    var uploadURL: URL?       // M-Lab: pre-signed wss upload URL
    var pingMs: Double?

    /// Short place label for the picker row.
    var shortPlace: String {
        switch provider {
        case .cloudflare: return "Nearest (auto)"
        case .mlab:       return country.isEmpty ? city : "\(city), \(country)"
        }
    }
    /// Sub-label naming the backbone/protocol.
    var detail: String {
        switch provider {
        case .cloudflare: return "Cloudflare · anycast edge"
        case .mlab:       return "M-Lab · NDT7"
        }
    }

    /// The always-available default: Cloudflare's nearest anycast edge.
    static let cloudflare = SpeedServer(
        id: "cloudflare", provider: .cloudflare, city: "", country: "",
        host: "speed.cloudflare.com", downloadURL: nil, uploadURL: nil, pingMs: nil)
}

@MainActor
@Observable
final class ServerDirectory {
    private(set) var servers: [SpeedServer] = [.cloudflare]
    var selectedID: SpeedServer.ID = SpeedServer.cloudflare.id
    private(set) var loading = false

    /// The currently-selected server (falls back to the first if the id is stale).
    var selected: SpeedServer {
        servers.first { $0.id == selectedID } ?? servers.first ?? .cloudflare
    }

    /// Rebuild the list (Cloudflare + nearby M-Lab cities) and ping each.
    func refresh() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }

        var list: [SpeedServer] = [.cloudflare]
        list += await MLabLocate.fetch()

        await withTaskGroup(of: (SpeedServer.ID, Double?).self) { group in
            for s in list {
                group.addTask { (s.id, await NetLatency.connect(host: s.host, port: 443)) }
            }
            for await (id, ms) in group {
                if let i = list.firstIndex(where: { $0.id == id }) { list[i].pingMs = ms }
            }
        }
        // Reachable servers first, then by ascending ping (display order only).
        list.sort { ($0.pingMs ?? .infinity) < ($1.pingMs ?? .infinity) }
        servers = list
        // Keep the user's pick if it's still present; otherwise fall back to the
        // privacy-preserving default (Cloudflare), NOT the lowest-ping server —
        // an M-Lab default would publish data without an explicit choice.
        if !list.contains(where: { $0.id == selectedID }) {
            selectedID = SpeedServer.cloudflare.id
        }
    }
}

/// M-Lab Locate API v2 — returns the nearest NDT7 machines with pre-signed,
/// access-token'd WebSocket URLs (no API key needed for the public endpoint).
enum MLabLocate {
    private struct Response: Decodable { let results: [Server]? }
    private struct Server: Decodable {
        let machine: String
        let location: Location?
        let urls: [String: String]
        struct Location: Decodable { let city: String?; let country: String? }
    }

    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 8
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()

    static func fetch() async -> [SpeedServer] {
        guard let url = URL(string: "https://locate.measurementlab.net/v2/nearest/ndt/ndt7") else { return [] }
        var req = URLRequest(url: url)
        req.setValue("NetScope-iOS/1.0 (network diagnostics)", forHTTPHeaderField: "User-Agent")
        guard let (d, _) = try? await session.data(for: req),
              let resp = try? JSONDecoder().decode(Response.self, from: d),
              let results = resp.results else { return [] }

        var out: [SpeedServer] = []
        for r in results {
            guard let dl = r.urls["wss:///ndt/v7/download"].flatMap(URL.init(string:)),
                  let ul = r.urls["wss:///ndt/v7/upload"].flatMap(URL.init(string:)) else { continue }
            out.append(SpeedServer(
                id: r.machine, provider: .mlab,
                city: r.location?.city ?? "Unknown",
                country: r.location?.country ?? "",
                host: dl.host ?? r.machine,
                downloadURL: dl, uploadURL: ul, pingMs: nil))
        }
        return out
    }
}

/// TCP-connect round-trip timing (no TLS), used to ping each candidate server.
enum NetLatency {
    static func connect(host: String, port: UInt16, timeout: Double = 4) async -> Double? {
        guard let p = NWEndpoint.Port(rawValue: port) else { return nil }
        return await withCheckedContinuation { (cont: CheckedContinuation<Double?, Never>) in
            let q = DispatchQueue(label: "netscope.connect")
            let conn = NWConnection(host: NWEndpoint.Host(host), port: p, using: .tcp)
            let gate = Once()
            let t0 = Date()
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if gate.fire() { let ms = Date().timeIntervalSince(t0) * 1000; conn.cancel(); cont.resume(returning: ms) }
                case .failed, .cancelled:
                    if gate.fire() { conn.cancel(); cont.resume(returning: nil) }
                default: break
                }
            }
            conn.start(queue: q)
            q.asyncAfter(deadline: .now() + timeout) {
                if gate.fire() { conn.cancel(); cont.resume(returning: nil) }
            }
        }
    }
}
