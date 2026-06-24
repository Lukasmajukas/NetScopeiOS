import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - CoverageMap speed-test backbone
//
// github.com/CoverageMapLLC/coveragemap-speed-test (Apache-2.0). Discovery:
//   GET https://api.speed.coveragemap.com/v1/connection   → client geolocation
//   GET .../v1/list?latitude=&longitude=                  → servers by proximity
// The test runs over wss://<domain>:<port>/v1/ws (PING/PONG, "START <kb> 500" download,
// binary-burst upload) — driven by SpeedTestEngine. After a run, the result is POSTed to
// map.coveragemap.com to contribute to the coverage map — ONLY after the in-app consent gate.

enum CoverageMap {
    static let apiBase   = "https://api.speed.coveragemap.com"
    static let reportURL = "https://map.coveragemap.com/api/v1/speedTests"
    /// Stable id identifying NetScope to CoverageMap (not a secret; just app attribution).
    static let appID = "netscope-ios"
    static let maxServers = 10   // nearest N — keeps the picker manageable

    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 8
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()

    private struct RawServer: Decodable {
        let id: String
        let domain: String
        let port: Int
        let city: String?
        let region: String?
        let country: String?
        let location: String?
        let premium: Bool?
    }
    private struct Connection: Decodable {
        struct Client: Decodable {
            let city: String?; let region: String?; let asOrg: String?
            let latitude: Double?; let longitude: Double?
        }
        struct Server: Decodable { let provider: String?; let dataCenter: String?; let city: String? }
        let client: Client?
        let server: Server?
    }

    /// Discovery: `/v1/connection` (geolocation + ISP + serving edge) → `/v1/list` (city servers).
    /// Returns the up-to-`maxServers` nearest non-premium servers AND the connection info, so the
    /// UI can surface "your ISP / location / nearest CoverageMap edge" without a second round-trip.
    static func discover() async -> (servers: [SpeedServer], connection: CMConnectionInfo?) {
        var lat: Double?, lon: Double?
        var info: CMConnectionInfo?
        if let url = URL(string: "\(apiBase)/v1/connection"),
           let (d, _) = try? await session.data(from: url),
           let c = try? JSONDecoder().decode(Connection.self, from: d) {
            lat = c.client?.latitude; lon = c.client?.longitude
            let place = [c.client?.city, c.client?.region].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
            let edge = c.server.flatMap { s in [s.city, s.dataCenter].compactMap { $0 }.first } ?? ""
            info = CMConnectionInfo(isp: c.client?.asOrg ?? "", place: place, edge: edge)
        }
        var listStr = "\(apiBase)/v1/list"
        if let lat, let lon { listStr += "?latitude=\(lat)&longitude=\(lon)" }
        guard let listURL = URL(string: listStr),
              let (d, _) = try? await session.data(from: listURL),
              let raw = try? JSONDecoder().decode([RawServer].self, from: d) else { return ([], info) }

        var out: [SpeedServer] = []
        for s in raw where !(s.premium ?? false) {       // premium servers need a paid account
            guard let url = URL(string: "wss://\(s.domain):\(s.port)/v1/ws") else { continue }
            let city = s.location ?? [s.city, s.region].compactMap { $0 }.joined(separator: ", ")
            out.append(SpeedServer(
                id: "cm-\(s.id)", provider: .coveragemap,
                city: city, country: s.country ?? "", host: s.domain,
                downloadURL: url, uploadURL: url, pingMs: nil))
            if out.count >= maxServers { break }          // list is distance-sorted
        }
        return (out, info)
    }

    /// Best-effort contribution of a completed result to the coverage map. Non-fatal on
    /// failure (the local result is already saved regardless).
    static func report(_ r: SpeedResult, server: SpeedServer) async {
        guard server.provider == .coveragemap else { return }
        let iso = ISO8601DateFormatter()
        let when = iso.string(from: r.date)
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1"

        let location: Any = (r.lat != nil && r.lon != nil)
            ? ["latitude": r.lat!, "longitude": r.lon!, "elevation": NSNull(), "heading": NSNull(),
               "speed": NSNull(), "locationType": "device"]
            : NSNull()

        let body: [String: Any] = [
            "source": "external",
            "version": 1,
            "device": [
                "id": NSNull(), "manufacturer": "Apple", "nameId": NSNull(),
                "name": deviceName(), "os": "iOS", "osVersion": osVersion(),
                "appName": "NetScope", "appVersion": appVersion,
                "application": ["id": appID, "name": "NetScope", "version": appVersion,
                                "organization": "NetScope", "type": "mobile", "website": NSNull()],
                "browserName": NSNull(), "browserVersion": NSNull(), "browserEngine": NSNull(),
                "browserEngineVersion": NSNull(), "cpuArchitecture": NSNull(), "cpuCores": NSNull(),
                "deviceMemoryGb": NSNull(), "deviceType": "mobile", "deviceVendor": "Apple",
                "deviceModel": NSNull(), "isMobile": true,
                "language": Locale.current.identifier, "timezone": TimeZone.current.identifier,
                "coreSystem": NSNull(),
            ],
            "testType": [
                "id": UUID().uuidString, "sessionId": UUID().uuidString, "type": "single",
                "testIndex": NSNull(), "testCount": NSNull(), "tag": "other",
                "testsRun": ["latency": true, "download": true, "upload": true],
                "downloadTestDuration": NSNull(), "uploadTestDuration": NSNull(),
                "testProtocol": "coveragemap-ws",
                "downloadConnectionCount": 4, "uploadConnectionCount": 4,
                "downloadPacketSize": 262144, "uploadPacketSize": 262144,
            ],
            "results": [
                "dateTime": when,
                "connectionType": connectionType(r),
                "externalIpAddress": orNull(r.ip),
                "ispName": orNull(r.isp),
                "testStatus": "passed",
                "location": location,
                "server": ["id": String(server.id.dropFirst(3)), "domain": server.host,
                           "port": 443, "location": server.city],
                "cellular": NSNull(), "wifi": NSNull(), "wired": NSNull(),
                "measurements": [
                    "dateTime": when,
                    "downloadSpeed": r.downloadMbps, "totalDownload": r.downloadBytes ?? 0,
                    "uploadSpeed": max(0, r.uploadMbps), "totalUpload": r.uploadBytes ?? 0,
                    "latency": r.pingMs, "jitter": r.jitterMs,
                    "latenciesList": NSNull(), "downloadList": NSNull(), "uploadList": NSNull(),
                    "failedReason": NSNull(), "failedStage": NSNull(),
                ],
            ],
            "stages": NSNull(),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: [body]),
              let url = URL(string: reportURL) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        _ = try? await session.data(for: req)
    }

    /// JSON value: the string, or NSNull when empty (so `JSONSerialization` emits `null`).
    private static func orNull(_ s: String) -> Any { s.isEmpty ? NSNull() : s }

    private static func connectionType(_ r: SpeedResult) -> String {
        let t = (r.connType ?? r.network).lowercased()
        if t.contains("wi-fi") || t.contains("wifi") { return "wifi" }
        if t.contains("ethernet") || t.contains("wired") { return "wired" }
        if t.contains("cell") || t.contains("5g") || t.contains("lte") || t.contains("4g")
            || t.contains("3g") || t.contains("nr") { return "mobile" }
        return "unknown"
    }

    private static func deviceName() -> String {
        #if canImport(UIKit)
        return UIDevice.current.model      // "iPhone"
        #else
        return "iPhone"
        #endif
    }
    private static func osVersion() -> String {
        #if canImport(UIKit)
        return UIDevice.current.systemVersion
        #else
        return ""
        #endif
    }
}
