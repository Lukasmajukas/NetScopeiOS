import SwiftUI
import Observation
import Network

// MARK: - Network tools
//
// A grab-bag of genuinely useful diagnostics iOS *does* allow without special
// entitlements: latency to well-known hosts (timed HTTPS, since ICMP needs raw
// sockets), DNS resolution via getaddrinfo, TCP reachability via NWConnection,
// and public-IP detail from ipinfo.io.

@MainActor
@Observable
final class ToolsModel {
    struct Ping: Identifiable {
        let id = UUID()
        let label: String
        let host: String
        var ms: Double? = nil
        var failed = false
    }
    var pings: [Ping] = [
        .init(label: "Cloudflare", host: "cloudflare.com"),
        .init(label: "Google",     host: "www.google.com"),
        .init(label: "Apple",      host: "www.apple.com"),
        .init(label: "Wikipedia",  host: "www.wikipedia.org"),
    ]
    var probing = false

    // DNS
    var dnsHost = "apple.com"
    var dnsResults: [String] = []
    var dnsLoading = false
    var dnsError = ""

    // Reachability
    var reachHost = "1.1.1.1"
    var reachPort = "443"
    var reachState = ""
    var reachOK: Bool?
    var reachChecking = false

    // Public IP
    var ip = ""
    var org = ""
    var hostName = ""
    var place = ""
    var ipLoading = false

    // MARK: Latency

    func probeAll() async {
        guard !probing else { return }
        probing = true
        defer { probing = false }
        for i in pings.indices { pings[i].ms = nil; pings[i].failed = false }
        await withTaskGroup(of: (Int, Double?).self) { group in
            for (i, p) in pings.enumerated() {
                group.addTask { (i, await Self.latency(p.host)) }
            }
            for await (i, ms) in group {
                if let ms { pings[i].ms = ms } else { pings[i].failed = true }
            }
        }
    }

    /// One shared ephemeral session for all probes — a per-call session would
    /// leak, since URLSessions retain themselves until explicitly invalidated.
    nonisolated static let probeSession: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 5
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()

    /// Best (minimum) of three timed HTTPS HEAD requests, in ms; nil on failure.
    nonisolated static func latency(_ host: String) async -> Double? {
        guard let url = URL(string: "https://\(host)/") else { return nil }
        var best: Double?
        for _ in 0..<3 {
            var req = URLRequest(url: url)
            req.httpMethod = "HEAD"
            let t0 = Date()
            if (try? await probeSession.data(for: req)) != nil {
                let ms = Date().timeIntervalSince(t0) * 1000
                best = min(best ?? ms, ms)
            }
        }
        return best
    }

    // MARK: DNS

    func lookupDNS() async {
        let host = dnsHost.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { return }
        dnsLoading = true; dnsError = ""
        defer { dnsLoading = false }
        let results = await Task.detached { Self.resolve(host) }.value
        if results.isEmpty { dnsError = "No records found"; dnsResults = [] }
        else { dnsResults = results }
    }

    nonisolated static func resolve(_ host: String) -> [String] {
        var hints = addrinfo(ai_flags: 0, ai_family: AF_UNSPEC, ai_socktype: SOCK_STREAM,
                             ai_protocol: 0, ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
        var info: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &info) == 0, let first = info else { return [] }
        defer { freeaddrinfo(info) }
        var out: [String] = []
        var p: UnsafeMutablePointer<addrinfo>? = first
        while let cur = p {
            defer { p = cur.pointee.ai_next }
            var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(cur.pointee.ai_addr, cur.pointee.ai_addrlen,
                           &buf, socklen_t(buf.count), nil, 0, NI_NUMERICHOST) == 0 {
                let s = String(cString: buf)
                if !s.isEmpty, !out.contains(s) { out.append(s) }
            }
        }
        return out
    }

    // MARK: Reachability (TCP connect)

    func checkReachable() async {
        let host = reachHost.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty,
              let portNum = UInt16(reachPort.trimmingCharacters(in: .whitespaces)), portNum > 0,
              let port = NWEndpoint.Port(rawValue: portNum) else {
            reachState = "Enter a host and a valid port (1–65535)"; reachOK = false; return
        }
        reachChecking = true; reachState = "Checking…"; reachOK = nil
        defer { reachChecking = false }

        let start = Date()
        let ok = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            // `Once` guarantees the continuation resumes exactly once, whether the
            // connection becomes ready/fails or the timeout fires first (no shared
            // mutable `var` captured across the concurrent closures).
            let q = DispatchQueue(label: "netscope.reach")
            let conn = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
            let gate = Once()
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if gate.fire() { cont.resume(returning: true); conn.cancel() }
                case .failed, .cancelled:
                    if gate.fire() { cont.resume(returning: false); conn.cancel() }
                default: break
                }
            }
            conn.start(queue: q)
            q.asyncAfter(deadline: .now() + 6) {
                if gate.fire() { conn.cancel(); cont.resume(returning: false) }
            }
        }
        if ok {
            reachState = "Reachable in \(Int(Date().timeIntervalSince(start) * 1000)) ms"
            reachOK = true
        } else {
            reachState = "Unreachable"
            reachOK = false
        }
    }

    // MARK: Public IP

    func loadIP() async {
        ipLoading = true
        defer { ipLoading = false }
        guard let url = URL(string: "https://ipinfo.io/json") else { return }
        var req = URLRequest(url: url); req.timeoutInterval = 8
        guard let (d, _) = try? await URLSession.shared.data(for: req),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
        ip = j["ip"] as? String ?? ""
        org = j["org"] as? String ?? ""
        hostName = j["hostname"] as? String ?? ""
        let city = j["city"] as? String ?? ""
        let region = j["region"] as? String ?? ""
        place = [city, region].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

// MARK: - View

struct ToolsView: View {
    @State private var model = ToolsModel()

    var body: some View {
        Screen("Tools") {
            latencyCard
            dnsCard
            reachCard
            publicIPCard
            Card {
                Text("Latency is measured over HTTPS (iOS apps can't send raw ICMP pings), so values include TLS setup and read a touch higher than a system ping — compare them to each other, not to Terminal.")
                    .font(.caption2).foregroundStyle(Color.nsFaint)
            }
        }
        .task {
            if model.pings.allSatisfy({ $0.ms == nil && !$0.failed }) { await model.probeAll() }
            if model.ip.isEmpty { await model.loadIP() }
        }
    }

    // Latency

    private var latencyCard: some View {
        Card {
            HStack {
                Text("LATENCY TO POPULAR SERVERS")
                    .font(.caption2.weight(.semibold)).tracking(1.1).foregroundStyle(Color.nsMuted)
                Spacer()
                Button { Task { await model.probeAll() } } label: {
                    Image(systemName: "arrow.clockwise")
                        .symbolEffect(.rotate, options: .repeating, isActive: model.probing)
                        .foregroundStyle(Color.nsAccent)
                }
                .disabled(model.probing)
            }
            ForEach(model.pings) { p in
                HStack(spacing: 10) {
                    Text(p.label).foregroundStyle(Color.nsTxt).frame(width: 90, alignment: .leading)
                    GeometryReader { geo in
                        let frac = barFraction(p.ms)
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.nsSurface2).frame(height: 6)
                            Capsule().fill(latencyColor(p.ms)).frame(width: geo.size.width * frac, height: 6)
                                .animation(.snappy, value: frac)
                        }
                        .frame(maxHeight: .infinity, alignment: .center)
                    }
                    .frame(height: 14)
                    Text(latencyText(p)).font(.caption.monospacedDigit())
                        .foregroundStyle(latencyColor(p.ms))
                        .frame(width: 64, alignment: .trailing)
                        .contentTransition(.numericText())
                }
                .font(.subheadline)
                .padding(.vertical, 4)
            }
        }
    }

    private func barFraction(_ ms: Double?) -> Double {
        guard let ms else { return 0 }
        return max(0.04, min(1, ms / 200))   // 0–200 ms scale
    }
    private func latencyColor(_ ms: Double?) -> Color {
        guard let ms else { return Color.nsFaint }
        if ms < 50 { return .nsOk }
        if ms < 150 { return Color(hex: 0xffa726) }
        return Color(hex: 0xff6b6b)
    }
    private func latencyText(_ p: ToolsModel.Ping) -> String {
        if p.failed { return "—" }
        guard let ms = p.ms else { return "…" }
        return "\(Int(ms.rounded())) ms"
    }

    // DNS

    private var dnsCard: some View {
        Card("DNS lookup") {
            HStack(spacing: 10) {
                TextField("hostname", text: Binding(get: { model.dnsHost }, set: { model.dnsHost = $0 }))
                    .textFieldStyle(.roundedBorder).autocorrectionDisabled()
                    .textInputAutocapitalization(.never).font(.callout)
                    .submitLabel(.go).onSubmit { Task { await model.lookupDNS() } }
                Button { Task { await model.lookupDNS() } } label: {
                    Group {
                        if model.dnsLoading { ProgressView().controlSize(.small) }
                        else { Text("Look up").font(.caption.weight(.semibold)) }
                    }
                    .foregroundStyle(Color.nsAccent)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .nsGlassCapsule()
                }
                .disabled(model.dnsLoading)
            }
            if !model.dnsError.isEmpty {
                Text(model.dnsError).font(.caption).foregroundStyle(Color.nsFaint)
            }
            ForEach(model.dnsResults, id: \.self) { ip in
                HStack(spacing: 8) {
                    Image(systemName: ip.contains(":") ? "6.circle" : "4.circle")
                        .foregroundStyle(Color.nsFaint).font(.caption)
                    Text(ip).font(.callout.monospaced()).foregroundStyle(Color.nsTxt)
                    Spacer()
                }
                .padding(.vertical, 2)
            }
        }
    }

    // Reachability

    private var reachCard: some View {
        Card("Host reachability") {
            Text("Open a TCP connection to a host and port to see if it's reachable (e.g. 443 = HTTPS, 22 = SSH).")
                .font(.caption).foregroundStyle(Color.nsMuted)
            HStack(spacing: 8) {
                TextField("host", text: Binding(get: { model.reachHost }, set: { model.reachHost = $0 }))
                    .textFieldStyle(.roundedBorder).autocorrectionDisabled()
                    .textInputAutocapitalization(.never).font(.callout)
                TextField("port", text: Binding(get: { model.reachPort }, set: { model.reachPort = $0 }))
                    .textFieldStyle(.roundedBorder).frame(width: 70).font(.callout)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                Button { Task { await model.checkReachable() } } label: {
                    Group {
                        if model.reachChecking { ProgressView().controlSize(.small) }
                        else { Text("Check").font(.caption.weight(.semibold)) }
                    }
                    .foregroundStyle(Color.nsAccent)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .nsGlassCapsule()
                }
                .disabled(model.reachChecking)
            }
            if !model.reachState.isEmpty {
                HStack(spacing: 6) {
                    if let ok = model.reachOK {
                        Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(ok ? Color.nsOk : Color(hex: 0xff6b6b))
                    }
                    Text(model.reachState).font(.caption)
                        .foregroundStyle(model.reachOK == false ? Color(hex: 0xff6b6b) : Color.nsTxt)
                }
            }
        }
    }

    // Public IP

    private var publicIPCard: some View {
        Card("Your public IP") {
            if model.ipLoading && model.ip.isEmpty {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Looking up…").font(.caption).foregroundStyle(Color.nsFaint) }
            } else {
                row("IP", model.ip.isEmpty ? "—" : model.ip)
                if !model.org.isEmpty { row("Network", model.org) }
                if !model.hostName.isEmpty { row("Reverse host", model.hostName) }
                if !model.place.isEmpty { row("Location", model.place) }
            }
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).foregroundStyle(Color.nsMuted)
            Spacer()
            Text(v).foregroundStyle(Color.nsTxt).multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.subheadline)
        .padding(.vertical, 5)
        .overlay(alignment: .bottom) { Divider().overlay(Color.nsLine) }
    }
}

/// A thread-safe one-shot latch: `fire()` returns true exactly once. Used to
/// resume a continuation from whichever of several concurrent callbacks wins.
final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    func fire() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if fired { return false }
        fired = true
        return true
    }
}
