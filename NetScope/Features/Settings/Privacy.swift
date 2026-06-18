import SwiftUI

// MARK: - Privacy Policy

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                legalHeader(
                    icon: "lock.shield.fill",
                    title: "Privacy Policy",
                    subtitle: "Last updated June 16, 2026"
                )
                legalCard("The short version") {
                    Text("NetScope has no servers and no analytics — the developer never receives, stores, or sells your data, and your results live on your device. Running a speed test does send your IP address to the test backbone (Cloudflare by default, or M-Lab if you choose an M-Lab location) and to ipinfo.io, as any speed test must. Important: if you choose an M-Lab location, that test — your IP address, the time, and your measured speeds — is published publicly by M-Lab as open data under a CC0 license, and that cannot be undone.")
                        .font(.subheadline)
                        .foregroundStyle(Color.nsTxt)
                }
                legalCard("What the app stores on your device") {
                    legalRow("bolt.fill", "Speed test results",
                             "Download, upload, ping, jitter, timestamp, network type. Kept until you clear them.")
                    legalRow("location.fill", "Location (optional)",
                             "GPS coordinates stamped on test results, only if you grant permission. Stored locally; never transmitted to the developer.")
                    legalRow("wifi", "Network details",
                             "Wi-Fi name (SSID), router ID (BSSID), signal strength, cellular carrier and generation.")
                    legalRow("globe", "IP addresses",
                             "Your public IP (from ipinfo.io and the test backbone) and local IP are stored in your on-device history. On the M-Lab path your public IP is also transmitted to and published by M-Lab — see Third-party services.")
                }
                legalCard("Third-party services") {
                    Text("External services are contacted when you open the Speed tab (to list nearby servers and measure their ping), pick a server, or run a test. None receives your name, precise location, device ID, or test history.")
                        .font(.caption).foregroundStyle(Color.nsMuted).padding(.bottom, 4)
                    thirdPartyRow("Cloudflare", "speed.cloudflare.com",
                                  "Default backbone. Runs the test and sees your IP and the test traffic.")
                    Divider().overlay(Color.nsLine)
                    thirdPartyRow("M-Lab (Measurement Lab)", "measurement-lab.org",
                                  "Optional open-source backbone you can select. IMPORTANT: M-Lab publishes every test it runs — including your IP address, the time, and the measured speeds — as an open public dataset under a CC0 license. Only used when you choose an M-Lab location.")
                    Divider().overlay(Color.nsLine)
                    thirdPartyRow("ipinfo.io", "ipinfo.io",
                                  "Returns your ISP name and approximate city from your IP address.")
                }
                legalCard("Permissions") {
                    permRow("Location", "When In Use",
                            "GPS coordinates are added to test results so you can see where each test was run. Tests work fine without it — lat/lon will be blank in exports.")
                    Divider().overlay(Color.nsLine)
                    permRow("Local Network", "On request",
                            "Required for the Devices tab to discover printers, TVs, and other gadgets on your Wi-Fi. The app never scans cellular networks.")
                }
                legalCard("Pro features (optional)") {
                    Text("These are off unless you turn them on, and each sends data only to a server address you enter yourself — never to the developer.")
                        .font(.caption).foregroundStyle(Color.nsMuted).padding(.bottom, 4)
                    legalRow("map.fill", "Coverage Map · Mac sync",
                             "If you enter a Mac server address, the app sends your coverage tiles (approximate, grid-rounded coordinates and average speeds — not raw GPS) to that server and shows the merged result. Leave it blank and nothing is sent.")
                    legalRow("building.2.crop.circle", "ISP Service enrichment",
                             "Uses sample data by default. If you enter an enrichment endpoint and token, your public IP address is sent to that address to look up plan details. Optional and blank by default.")
                }
                legalCard("Data you export") {
                    Text("The CSV export is created in your device's temporary storage and shared only when you tap Export — the developer never receives it.")
                        .font(.caption).foregroundStyle(Color.nsMuted)
                }
                legalCard("Children") {
                    Text("NetScope is not directed at children under 13 and does not knowingly collect information from children.")
                        .font(.caption).foregroundStyle(Color.nsMuted)
                }
                legalCard("Changes") {
                    Text("If this policy changes, the updated version will be available in the app and the date above will be updated.")
                        .font(.caption).foregroundStyle(Color.nsMuted)
                }
                legalCard("Contact") {
                    Label("odonnelldigger1@gmail.com", systemImage: "envelope")
                        .font(.caption).foregroundStyle(Color.nsAccent)
                }
            }
            .padding(16)
        }
        .background(Color.nsBg.ignoresSafeArea())
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
        #if os(iOS)
        .toolbarBackground(Color.nsBg, for: .navigationBar)
        #endif
    }

    private func legalRow(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Color.nsAccent).frame(width: 20).padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(Color.nsTxt)
                Text(detail).font(.caption).foregroundStyle(Color.nsMuted)
            }
        }
        .padding(.vertical, 4)
    }

    private func thirdPartyRow(_ name: String, _ domain: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(name).font(.subheadline.weight(.semibold)).foregroundStyle(Color.nsTxt)
                Spacer()
                Text(domain).font(.caption2).foregroundStyle(Color.nsFaint)
            }
            Text(detail).font(.caption).foregroundStyle(Color.nsMuted)
        }
        .padding(.vertical, 4)
    }

    private func permRow(_ name: String, _ level: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(name).font(.subheadline.weight(.semibold)).foregroundStyle(Color.nsTxt)
                Spacer()
                Text(level).font(.caption.weight(.medium)).foregroundStyle(Color.nsAccent)
            }
            Text(detail).font(.caption).foregroundStyle(Color.nsMuted)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Terms of Use

struct TermsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                legalHeader(
                    icon: "doc.text.fill",
                    title: "Terms of Use",
                    subtitle: "Last updated June 16, 2026"
                )
                legalCard("Acceptance") {
                    Text("By downloading or using NetScope you agree to these terms. If you do not agree, do not use the app.")
                        .font(.subheadline).foregroundStyle(Color.nsTxt)
                }
                legalCard("Use of the app") {
                    bulletRow("NetScope is a free tool for personal, non-commercial network diagnostics.")
                    bulletRow("Speed test results reflect conditions at the time of the test and are not a guarantee of typical or maximum performance.")
                    bulletRow("Do not rely on these results for safety-critical decisions.")
                    bulletRow("You may not reverse engineer, modify, or redistribute the app.")
                }
                legalCard("Third-party services") {
                    Text("When you run a speed test, traffic passes through the selected backbone — Cloudflare by default, or M-Lab (Measurement Lab) if you choose an M-Lab location — and your IP address is sent to ipinfo.io. Tests run against M-Lab become part of M-Lab's openly published, CC0-licensed measurement dataset. Your use of those services is subject to their respective terms and privacy policies. The developer is not responsible for those services.")
                        .font(.caption).foregroundStyle(Color.nsMuted)
                }
                legalCard("No warranty") {
                    Text("NetScope is provided \"as is\" without warranty of any kind, express or implied, including but not limited to warranties of merchantability, fitness for a particular purpose, or accuracy.")
                        .font(.caption).foregroundStyle(Color.nsMuted)
                }
                legalCard("Limitation of liability") {
                    Text("To the maximum extent permitted by law, the developer shall not be liable for any indirect, incidental, special, consequential, or punitive damages arising from your use of, or inability to use, the app.")
                        .font(.caption).foregroundStyle(Color.nsMuted)
                }
                legalCard("Governing law") {
                    Text("These terms are governed by the laws of the jurisdiction in which the developer is located, without regard to conflict-of-law provisions.")
                        .font(.caption).foregroundStyle(Color.nsMuted)
                }
                legalCard("Changes") {
                    Text("These terms may be updated at any time. Continued use of the app after changes constitutes acceptance. The date above reflects the most recent revision.")
                        .font(.caption).foregroundStyle(Color.nsMuted)
                }
                legalCard("Contact") {
                    Label("odonnelldigger1@gmail.com", systemImage: "envelope")
                        .font(.caption).foregroundStyle(Color.nsAccent)
                }
            }
            .padding(16)
        }
        .background(Color.nsBg.ignoresSafeArea())
        .navigationTitle("Terms of Use")
        .navigationBarTitleDisplayMode(.inline)
        #if os(iOS)
        .toolbarBackground(Color.nsBg, for: .navigationBar)
        #endif
    }

    private func bulletRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•").foregroundStyle(Color.nsAccent).font(.subheadline)
            Text(text).font(.subheadline).foregroundStyle(Color.nsTxt)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Shared helpers (file-private)

private func legalHeader(icon: String, title: String, subtitle: String) -> some View {
    HStack(spacing: 14) {
        Image(systemName: icon).font(.system(size: 32)).foregroundStyle(Color.nsAccent)
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.title2.weight(.bold)).foregroundStyle(Color.nsTxt)
            Text(subtitle).font(.caption).foregroundStyle(Color.nsFaint)
        }
        Spacer()
    }
    .padding(.bottom, 4)
}

private func legalCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold)).tracking(1.1).foregroundStyle(Color.nsMuted)
        content()
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.nsSurface, in: RoundedRectangle(cornerRadius: 18))
    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.nsLine, lineWidth: 1))
}
