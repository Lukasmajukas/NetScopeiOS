import SwiftUI

// Colour palette mirrored from the macOS NetScope dashboard.
extension Color {
    init(hex: UInt) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
    static let nsBg       = Color(hex: 0x0a0e16)
    static let nsSurface  = Color(hex: 0x121826)
    static let nsSurface2 = Color(hex: 0x1a2233)
    static let nsLine     = Color(hex: 0x232d44)
    static let nsTxt      = Color(hex: 0xe7ecf6)
    static let nsMuted    = Color(hex: 0x8a96ad)
    static let nsFaint    = Color(hex: 0x5b6680)
    static let nsAccent   = Color(hex: 0x5b9dff)
    static let nsOk       = Color(hex: 0x37d67a)
    static let nsB24      = Color(hex: 0xf5a623)   // 2.4 GHz
    static let nsB5       = Color(hex: 0x4f9dff)   // 5 GHz
    static let nsB6       = Color(hex: 0xa06bff)   // 6 GHz
}

// MARK: - Liquid Glass helper (iOS 26+)

extension View {
    /// Liquid Glass capsule for action buttons. Available under the iOS-27 target.
    func nsGlassCapsule(tinted: Bool = true) -> some View {
        glassEffect(tinted ? .regular.tint(.nsAccent) : .regular, in: .capsule)
    }
}

// A standard dark card container used across the app.
struct Card<Content: View>: View {
    let title: String?
    @ViewBuilder var content: Content
    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                Text(title.uppercased())
                    .font(.caption2.weight(.semibold))
                    .tracking(1.1)
                    .foregroundStyle(Color.nsMuted)
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.nsSurface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.nsLine, lineWidth: 1))
        // Subtle scroll-in: cards ease/scale into place as they enter the viewport.
        .scrollTransition(.interactive, axis: .vertical) { view, phase in
            view
                .opacity(phase.isIdentity ? 1 : 0.35)
                .scaleEffect(phase.isIdentity ? 1 : 0.97)
        }
    }
}

// A screen scaffold: dark background + scrollable content + large title.
// Pass `trailing:` to place a view in the navigation bar's trailing slot.
struct Screen<Content: View>: View {
    let title: String
    var trailingButton: AnyView? = nil
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    init<B: View>(_ title: String, trailing: B, @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailingButton = AnyView(trailing)
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) { content }
                    .padding(16)
            }
            .background(Color.nsBg.ignoresSafeArea())
            .navigationTitle(title)
            #if os(iOS)
            .toolbarBackground(Color.nsBg, for: .navigationBar)
            #endif
            .toolbar {
                if let b = trailingButton {
                    ToolbarItem(placement: .topBarTrailing) { b }
                }
            }
        }
    }
}
