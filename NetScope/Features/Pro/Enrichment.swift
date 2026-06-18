import SwiftUI
import Observation

// MARK: - Ookla Provider Enrichment schema
//
// Mirrors the `SubscriberServiceResponse` from Ookla's Speedtest Provider
// Enrichment API (openapi.json). IMPORTANT: that API is a *provider-side*
// contract — Ookla calls an ISP's `/subscriber-service` endpoint to enrich a
// test; it is NOT an endpoint a consumer app can post results to. A normal
// subscriber has no way to authenticate against their ISP's enrichment service,
// so by default we render representative SAMPLE data (clearly labelled). The
// optional client below will hit a real endpoint if one is configured.

struct SubscriberServiceResponse: Codable {
    var type: String?            // "residential" | "commercial"
    var technology: String?      // "fttp", "docsis-3.1", "leo-satellite", …
    var display: Display?
    var location: ServiceLocation?

    struct Display: Codable {
        var provisioned: Provisioned?
        var brand: String?
        var supportUrl: String?
        var isThrottled: Bool?
    }
    struct Provisioned: Codable {
        var downloadMbps: Int?
        var uploadMbps: Int?
    }
    struct ServiceLocation: Codable {
        var latitude: Double?
        var longitude: Double?
        var source: String?       // "gps" | "network" | "geoip" | "address"
    }

    /// Representative sample straight from the spec's examples — used in preview.
    static let sample = SubscriberServiceResponse(
        type: "residential",
        technology: "fttp",
        display: .init(
            provisioned: .init(downloadMbps: 1024, uploadMbps: 1024),
            brand: "Speedtest Fiber",
            supportUrl: "https://www.speedtest.net/",
            isThrottled: false),
        location: .init(latitude: 47.62, longitude: -122.34, source: "geoip"))
}

/// Human label for the `technology` enum values in the spec.
func technologyLabel(_ raw: String?) -> String {
    switch raw {
    case "fttp":                 return "Fiber (FTTP)"
    case "docsis-2.0":           return "Cable (DOCSIS 2.0)"
    case "docsis-3.0":           return "Cable (DOCSIS 3.0)"
    case "docsis-3.1":           return "Cable (DOCSIS 3.1)"
    case "docsis-4.0":           return "Cable (DOCSIS 4.0)"
    case "docsis":               return "Cable (DOCSIS)"
    case "adsl", "vdsl", "sdsl", "dsl": return "DSL"
    case "copper":               return "Copper"
    case "leo-satellite":        return "Satellite (LEO)"
    case "satellite":            return "Satellite"
    case "fixed-cellular-5g":    return "Fixed Wireless 5G"
    case "fixed-cellular-4g":    return "Fixed Wireless 4G"
    case "fixed-cellular-3g":    return "Fixed Wireless 3G"
    case "fixed-cellular":       return "Fixed Wireless"
    case "mobile-cellular":      return "Mobile"
    case .some(let other) where !other.isEmpty: return other.capitalized
    default:                     return "—"
    }
}

// MARK: - Optional real enrichment client
//
// Hits an enrichment endpoint if one is configured (advanced; most users leave
// it blank and see the sample). Auth is a bearer token per the spec.

@MainActor
@Observable
final class EnrichmentClient {
    var result: SubscriberServiceResponse = .sample
    var isSample = true
    var loading = false

    func load(endpoint: String, token: String, ipv4: String) async {
        let ep = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ep.isEmpty, !ipv4.isEmpty,
              var comps = URLComponents(string: ep.hasSuffix("/subscriber-service")
                                        ? ep : ep + "/subscriber-service") else {
            result = .sample; isSample = true; return
        }
        comps.queryItems = [URLQueryItem(name: "ipv4", value: ipv4)]
        guard let url = comps.url else { result = .sample; isSample = true; return }

        loading = true
        defer { loading = false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        if !token.isEmpty { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(SubscriberServiceResponse.self, from: data) else {
            result = .sample; isSample = true; return
        }
        result = decoded
        isSample = false
    }
}

// MARK: - ISP Service card (Pro)

struct ISPServiceCard: View {
    /// The user's last measured download, to compare against the provisioned plan.
    var lastDownload: Double?
    var enrichment: SubscriberServiceResponse
    var isSample: Bool

    var body: some View {
        Card {
            HStack(spacing: 8) {
                Text("ISP SERVICE")
                    .font(.caption2.weight(.semibold)).tracking(1.1)
                    .foregroundStyle(Color.nsMuted)
                ProBadge()
                Spacer()
                if isSample {
                    Text("SAMPLE")
                        .font(.system(size: 9, weight: .bold)).tracking(0.5)
                        .foregroundStyle(Color.nsFaint)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .overlay(Capsule().strokeBorder(Color.nsLine, lineWidth: 1))
                }
            }

            if let brand = enrichment.display?.brand, !brand.isEmpty {
                row("Plan", brand)
            }
            row("Technology", technologyLabel(enrichment.technology))
            if let p = enrichment.display?.provisioned {
                row("Provisioned", provisionedText(p))
            }
            if let last = lastDownload, last > 0,
               let prov = enrichment.display?.provisioned?.downloadMbps, prov > 0 {
                row("Your last test", deliveredText(last: last, provisioned: Double(prov)))
            }
            if let throttled = enrichment.display?.isThrottled {
                throttleRow(throttled)
            }

            if isSample {
                Text("Sample data. Real provider enrichment is served by your ISP to Ookla — not available to consumer apps. Add an endpoint in Settings if you have one.")
                    .font(.caption2).foregroundStyle(Color.nsFaint)
            }
        }
    }

    private func provisionedText(_ p: SubscriberServiceResponse.Provisioned) -> String {
        let d = p.downloadMbps.map { "\($0)" } ?? "—"
        let u = p.uploadMbps.map { "\($0)" } ?? "—"
        return "\(d) ↓ / \(u) ↑ Mbps"
    }

    private func deliveredText(last: Double, provisioned: Double) -> String {
        let pct = Int((last / provisioned * 100).rounded())
        return "\(Int(last.rounded())) Mbps · \(pct)% of plan"
    }

    private func throttleRow(_ throttled: Bool) -> some View {
        HStack {
            Text("Throttled").foregroundStyle(Color.nsMuted)
            Spacer()
            Text(throttled ? "Yes" : "No")
                .foregroundStyle(throttled ? Color(hex: 0xff6b6b) : Color.nsOk)
                .fontWeight(.semibold)
        }
        .font(.subheadline)
        .padding(.vertical, 5)
        .overlay(alignment: .bottom) { Divider().overlay(Color.nsLine) }
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
