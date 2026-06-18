import SwiftUI
import CoreLocation

struct SettingsView: View {
    @Environment(HistoryStore.self) private var history
    @Environment(LocationProvider.self) private var location
    @Environment(ProManager.self) private var pro
    @Environment(\.dismiss) private var dismiss

    @AppStorage("startTab")  private var startTab  = 0
    @AppStorage("autorun")   private var autorun   = false
    @AppStorage("enrichEndpoint") private var enrichEndpoint = ""
    @AppStorage("enrichToken")    private var enrichToken    = ""
    @State private var showClearConfirm = false
    @State private var showProAdvanced = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    proCard
                    permissionsCard
                    dataCard
                    preferencesCard
                    aboutCard
                }
                .padding(16)
            }
            .background(Color.nsBg.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            #if os(iOS)
            .toolbarBackground(Color.nsBg, for: .navigationBar)
            #endif
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.nsAccent)
                }
            }
        }
        .preferredColorScheme(.dark)
        .confirmationDialog("Clear all saved speed tests?",
                            isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("Clear History", role: .destructive) { history.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
    }

    // MARK: - Pro

    private var proCard: some View {
        Card {
            HStack(spacing: 10) {
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(LinearGradient(
                        colors: [Color.nsOk, Color.nsAccent],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                Text("NetScope Pro")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Color.nsTxt)
                Spacer()
                ProBadge()
            }
            Divider().overlay(Color.nsLine)
            Toggle(isOn: Binding(get: { pro.isPro },
                                 set: { v in withAnimation { pro.isPro = v } })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pro.purchaseAvailable ? "Pro" : "Pro features (Preview)")
                        .font(.subheadline).foregroundStyle(Color.nsTxt)
                    Text("Unlocks the Coverage Map and ISP Service insights.")
                        .font(.caption).foregroundStyle(Color.nsMuted)
                }
            }
            .tint(Color.nsAccent)

            if !pro.purchaseAvailable {
                Text("A real purchase needs the Apple Developer Program + StoreKit, so this preview switch unlocks Pro for evaluation. Buying replaces this toggle once In-App Purchase is set up.")
                    .font(.caption2).foregroundStyle(Color.nsFaint)
            }

            if pro.isPro {
                Divider().overlay(Color.nsLine)
                Button {
                    withAnimation { showProAdvanced.toggle() }
                } label: {
                    HStack {
                        Text("Advanced: ISP enrichment endpoint")
                            .font(.caption.weight(.medium)).foregroundStyle(Color.nsAccent)
                        Spacer()
                        Image(systemName: showProAdvanced ? "chevron.up" : "chevron.down")
                            .font(.caption2).foregroundStyle(Color.nsFaint)
                    }
                }
                if showProAdvanced {
                    Text("Optional. The ISP Service card uses sample data by default — a consumer app can't reach an ISP's private Ookla enrichment service. If you operate one, point at it here.")
                        .font(.caption2).foregroundStyle(Color.nsFaint)
                    TextField("https://…/subscriber-service", text: $enrichEndpoint)
                        .textFieldStyle(.roundedBorder).autocorrectionDisabled()
                        .textInputAutocapitalization(.never).font(.caption)
                    SecureField("Bearer token (optional)", text: $enrichToken)
                        .textFieldStyle(.roundedBorder).font(.caption)
                }
            }
        }
    }

    // MARK: - Permissions

    private var permissionsCard: some View {
        Card("Permissions") {
            locationRow
            Divider().overlay(Color.nsLine)
            localNetworkRow
        }
    }

    private var locationRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "location.fill")
                .foregroundStyle(locationIconColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Location")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.nsTxt)
                Text(locationSubtitle)
                    .font(.caption)
                    .foregroundStyle(Color.nsMuted)
            }
            Spacer()
            locationAction
        }
        .padding(.vertical, 4)
    }

    private var locationIconColor: Color {
        switch location.status {
        case .authorizedWhenInUse, .authorizedAlways: return .nsOk
        case .denied, .restricted: return Color(hex: 0xff6b6b)
        default: return .nsMuted
        }
    }

    private var locationSubtitle: String {
        switch location.status {
        case .authorizedWhenInUse, .authorizedAlways:
            return "Allowed — lat/lon saved with speed tests"
        case .denied, .restricted:
            return "Denied — speed tests won't include location"
        case .notDetermined:
            return "Not asked — needed to stamp test results"
        @unknown default:
            return "Unknown"
        }
    }

    @ViewBuilder
    private var locationAction: some View {
        switch location.status {
        case .authorizedWhenInUse, .authorizedAlways:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.nsOk)
        case .denied, .restricted:
            Button("Open Settings") { openSettings() }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.nsAccent)
        case .notDetermined:
            Button("Allow") { location.start() }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.nsAccent)
        @unknown default:
            EmptyView()
        }
    }

    private var localNetworkRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "network")
                .foregroundStyle(Color.nsMuted)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Local Network")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.nsTxt)
                Text("Needed for device discovery on Wi-Fi")
                    .font(.caption)
                    .foregroundStyle(Color.nsMuted)
            }
            Spacer()
            Button("Open Settings") { openSettings() }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.nsAccent)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Data

    private var dataCard: some View {
        Card("Data") {
            HStack {
                Text("Saved tests")
                    .font(.subheadline)
                    .foregroundStyle(Color.nsMuted)
                Spacer()
                Text("\(history.items.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.nsTxt)
                    .monospacedDigit()
            }
            .padding(.vertical, 2)
            Divider().overlay(Color.nsLine)
            HStack(spacing: 12) {
                if let url = history.csvFileURL() {
                    ShareLink(item: url) {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.nsAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.nsSurface2, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                Button(role: .destructive) {
                    showClearConfirm = true
                } label: {
                    Label("Clear History", systemImage: "trash")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(history.items.isEmpty ? Color.nsFaint : Color(hex: 0xff6b6b))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.nsSurface2, in: RoundedRectangle(cornerRadius: 10))
                }
                .disabled(history.items.isEmpty)
            }
        }
    }

    // MARK: - Preferences

    private var preferencesCard: some View {
        Card("Preferences") {
            VStack(spacing: 0) {
                HStack {
                    Text("Default tab")
                        .font(.subheadline)
                        .foregroundStyle(Color.nsMuted)
                    Spacer()
                }
                Picker("Default tab", selection: $startTab) {
                    Text("Speed").tag(0)
                    Text("Devices").tag(1)
                    Text("Connection").tag(2)
                    Text("Learn").tag(3)
                }
                .pickerStyle(.segmented)
                .padding(.top, 8)
                Text("Takes effect next launch.")
                    .font(.caption2)
                    .foregroundStyle(Color.nsFaint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
            Divider().overlay(Color.nsLine).padding(.vertical, 4)
            Toggle(isOn: $autorun) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-run on launch")
                        .font(.subheadline)
                        .foregroundStyle(Color.nsTxt)
                    Text("Starts a speed test automatically when the app opens.")
                        .font(.caption)
                        .foregroundStyle(Color.nsMuted)
                }
            }
            .tint(Color.nsAccent)
        }
    }

    // MARK: - About

    private var aboutCard: some View {
        Card("About") {
            HStack {
                Text("NetScope")
                    .font(.subheadline)
                    .foregroundStyle(Color.nsMuted)
                Spacer()
                Text("Version \(appVersion)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.nsTxt)
                    .monospacedDigit()
            }
            .padding(.vertical, 2)
            Divider().overlay(Color.nsLine)
            attributionRow("Speed test", "Cloudflare speed.cloudflare.com", "bolt.fill")
            Divider().overlay(Color.nsLine)
            attributionRow("IP & location data", "ipinfo.io", "globe")
            Divider().overlay(Color.nsLine)
            NavigationLink(destination: PrivacyPolicyView()) {
                legalNavRow("Privacy Policy", "lock.shield")
            }
            Divider().overlay(Color.nsLine)
            NavigationLink(destination: TermsView()) {
                legalNavRow("Terms of Use", "doc.text")
            }
        }
    }

    private func legalNavRow(_ title: String, _ icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Color.nsAccent).frame(width: 18)
            Text(title)
                .font(.subheadline).foregroundStyle(Color.nsTxt)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold)).foregroundStyle(Color.nsFaint)
        }
        .padding(.vertical, 4)
    }

    private func attributionRow(_ label: String, _ value: String, _ icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Color.nsFaint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(Color.nsMuted)
                Text(value)
                    .font(.caption2)
                    .foregroundStyle(Color.nsFaint)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    // MARK: - Helpers

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        // e.g. "1.0 (1)" — marketing version with the build number, both from the
        // MARKETING_VERSION / CURRENT_PROJECT_VERSION build settings via Info.plist.
        return "\(short) (\(build))"
    }

    private func openSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }
}
