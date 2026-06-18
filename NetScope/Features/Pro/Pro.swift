import SwiftUI
import Observation

// MARK: - Pro gating
//
// NetScope Pro unlocks the Coverage Map (speed tiles) and ISP Service insights.
//
// A real paid tier requires StoreKit 2 + a non-consumable product configured in
// App Store Connect, which in turn needs a paid Apple Developer Program
// membership. Until that's set up, Pro is unlocked by a *preview* switch in
// Settings so the features can be evaluated. The gate is centralised here so a
// real `Transaction.currentEntitlements` check can replace the stored flag
// without touching any feature code — every view just reads `pro.isPro`.

@MainActor
@Observable
final class ProManager {
    /// Whether Pro features are unlocked. Backed by UserDefaults today; swap the
    /// getter for a StoreKit entitlement check when IAP is wired up.
    var isPro: Bool {
        didSet { UserDefaults.standard.set(isPro, forKey: Self.key) }
    }

    /// True once a real StoreKit product is available (always false in preview).
    let purchaseAvailable = false

    @ObservationIgnored private static let key = "proEnabled"

    init() {
        isPro = UserDefaults.standard.bool(forKey: Self.key)
    }
}

// MARK: - Shared Pro UI

/// A small "PRO" pill used to tag gated features.
struct ProBadge: View {
    var body: some View {
        Text("PRO")
            .font(.caption2.weight(.bold))
            .tracking(0.5)
            .foregroundStyle(Color(hex: 0x04122e))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                LinearGradient(colors: [Color.nsOk, Color.nsAccent],
                               startPoint: .leading, endPoint: .trailing),
                in: Capsule())
    }
}

/// A teaser card shown where a Pro feature would appear, when Pro is locked.
/// Tapping "Enable" flips the preview switch directly so the user can try it.
struct ProLockedCard: View {
    let title: String
    let blurb: String
    let icon: String
    @Environment(ProManager.self) private var pro

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 26))
                    .foregroundStyle(Color.nsAccent)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.nsTxt)
                        ProBadge()
                    }
                    Text(blurb)
                        .font(.caption)
                        .foregroundStyle(Color.nsMuted)
                    Button {
                        withAnimation { pro.isPro = true }
                    } label: {
                        Text("Enable Pro (Preview)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.nsAccent)
                    }
                    .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
        }
    }
}
