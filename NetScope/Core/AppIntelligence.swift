import SwiftUI
import Observation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Apple Intelligence summary
//
// Uses Apple's on-device Foundation Models (Apple Intelligence) to turn a raw speed-test
// result into a friendly, plain-English read on what the connection is good for. It runs
// ENTIRELY ON-DEVICE — nothing is sent off the phone — and degrades gracefully on devices
// where Apple Intelligence isn't available/enabled (the card simply hides).

@MainActor
@Observable
final class AISummarizer {
    enum State: Equatable {
        case idle, generating
        case done(String)
        case failed(String)
    }
    var state: State = .idle

    /// True only when the on-device model is present AND enabled by the user.
    var isAvailable: Bool {
        #if canImport(FoundationModels)
        if case .available = SystemLanguageModel.default.availability { return true }
        #endif
        return false
    }

    func summarize(_ r: SpeedResult) async {
        #if canImport(FoundationModels)
        guard case .available = SystemLanguageModel.default.availability else {
            state = .failed("Apple Intelligence isn't available on this device.")
            return
        }
        state = .generating
        let facts = """
        Download: \(Int(r.downloadMbps.rounded())) Mbps
        Upload: \(Int(max(0, r.uploadMbps).rounded())) Mbps
        Ping: \(Int(r.pingMs.rounded())) ms (jitter \(Int(r.jitterMs.rounded())) ms)
        Connection: \(r.connType ?? r.network)
        """
        let prompt = """
        Here is an internet speed-test result:
        \(facts)
        In 2–3 short sentences, explain in plain, friendly language what this connection is \
        good (or not good) for in everyday use — 4K streaming, video calls, online gaming, \
        large downloads/uploads, multiple devices. Be specific to these numbers and \
        encouraging. Do not just restate the numbers as a list.
        """
        do {
            let session = LanguageModelSession(
                instructions: "You are a concise, friendly network assistant inside a speed-test app. You give brief, practical, jargon-free interpretations of connection quality.")
            let response = try await session.respond(to: prompt)
            state = .done(response.content.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            state = .failed("Couldn't generate a summary just now.")
        }
        #else
        state = .failed("Requires iOS 26+ with Apple Intelligence.")
        #endif
    }

    func reset() { state = .idle }
}
