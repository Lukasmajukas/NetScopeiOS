import SwiftUI

struct LearnView: View {
    var body: some View {
        Screen("Learn") {
            explainer(.nsB24, "2.4 GHz band",
                "Travels the farthest and through walls best, but it’s the slowest band and the most crowded — Bluetooth, microwaves and most smart-home gadgets all share it. Real-world speeds are often under 100 Mbps.")
            explainer(.nsB5, "5 GHz band",
                "The sweet spot most modern devices use: several times faster than 2.4 GHz with solid range for a typical home. Slightly weaker through walls than 2.4 GHz.")
            explainer(.nsB6, "6 GHz band",
                "The newest band, used only by Wi-Fi 6E and Wi-Fi 7 gear. The cleanest airwaves and the highest speeds, but the shortest range — it shines in the same room as the router.")
            Card("Channel width") {
                Text("Channel width is how much of the airwaves your connection uses at once — like lanes on a road. 20 MHz is a single lane; each step up roughly doubles the top speed:")
                    .font(.caption).foregroundStyle(Color.nsMuted)
                ForEach(widths, id: \.0) { w in
                    HStack {
                        Text(w.0).foregroundStyle(Color.nsTxt).frame(width: 70, alignment: .leading)
                        Text(w.1).foregroundStyle(Color.nsMuted)
                        Spacer()
                    }.font(.caption)
                }
            }
            Card("What the speeds mean") {
                bullet("Download", "how fast data comes to you — streaming, browsing, downloads. The number most people care about.")
                bullet("Upload", "how fast data leaves you — video calls, posting, backups, cloud sync.")
                bullet("Ping", "round-trip delay in milliseconds. Lower is snappier; under ~40 ms feels instant, and it matters most for gaming and calls.")
                bullet("Jitter", "how much the ping wobbles. High jitter causes choppy calls even if the average ping looks fine.")
            }

            topic("globe", "DNS — the internet's address book",
                "Before your device can load a site it asks a DNS server to turn the name (apple.com) into an IP address. Slow or flaky DNS makes pages feel sluggish even on a fast connection. The Tools tab can resolve a name and show the answers.")
            topic("gauge.with.needle", "Latency vs. bandwidth",
                "Bandwidth is how much data fits through at once (Mbps); latency is how long a round trip takes (ms). A 1 Gbps link with 200 ms latency still feels slow for calls and gaming — for those, low latency matters more than raw speed.")
            topic("6.circle", "IPv6",
                "The internet is running out of old-style IPv4 addresses, so networks are rolling out IPv6 — vastly more addresses and often a more direct path. Most modern carriers and ISPs now hand out IPv6; the Connection tab shows whether yours is active.")
            topic("lock.shield", "VPNs",
                "A VPN tunnels your traffic through another server, hiding your IP and encrypting the hop to that server. It usually adds a little latency and can cap speed, since everything detours through the VPN. NetScope flags when a test ran over a VPN.")
            topic("speedometer", "Throttling",
                "Some ISPs deliberately slow specific traffic (video, certain apps, or once you pass a data cap). If streaming is slow but your speed test is fast — or vice-versa — throttling may be the cause. Running tests at different times helps spot a pattern.")

            Card("Good numbers to aim for") {
                aim("Video calls", "3–5 Mbps up & down · ping < 100 ms · jitter < 30 ms")
                aim("HD / 4K streaming", "5 Mbps for HD, 25 Mbps for 4K per stream")
                aim("Online gaming", "ping < 50 ms matters far more than raw speed")
                aim("Big downloads / backups", "the more download (and upload) Mbps the better")
            }
        }
    }

    private func topic(_ icon: String, _ title: String, _ body: String) -> some View {
        Card {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon).foregroundStyle(Color.nsAccent).frame(width: 22).padding(.top, 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline).foregroundStyle(Color.nsTxt)
                    Text(body).font(.caption).foregroundStyle(Color.nsMuted)
                }
            }
        }
    }

    private func aim(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(k).font(.subheadline.weight(.semibold)).foregroundStyle(Color.nsTxt)
            Text(v).font(.caption).foregroundStyle(Color.nsMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }

    private let widths: [(String, String)] = [
        ("20 MHz", "most reliable in crowded areas — the baseline"),
        ("40 MHz", "~2× the speed of 20 MHz"),
        ("80 MHz", "~4× — common on 5 GHz"),
        ("160 MHz", "~8× — Wi-Fi 6/6E in clean air"),
        ("320 MHz", "~16× — Wi-Fi 7 only")
    ]

    private func explainer(_ color: Color, _ title: String, _ body: String) -> some View {
        Card {
            HStack(spacing: 10) {
                Circle().fill(color).frame(width: 10, height: 10)
                Text(title).font(.headline).foregroundStyle(Color.nsTxt)
            }
            Text(body).font(.caption).foregroundStyle(Color.nsMuted)
        }
    }

    private func bullet(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(k).font(.subheadline.weight(.semibold)).foregroundStyle(Color.nsTxt)
            Text(v).font(.caption).foregroundStyle(Color.nsMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }
}
