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
        }
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
