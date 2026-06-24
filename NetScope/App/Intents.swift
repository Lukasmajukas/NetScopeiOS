import AppIntents
import Foundation

// MARK: - Siri / Spotlight / Shortcuts integration
//
// App Intents expose NetScope to Siri, Spotlight, the Shortcuts app, and Apple
// Intelligence. Two actions: run a speed test (opens the app and auto-starts), and
// speak/return the last saved result. AppShortcuts make them usable by voice with
// zero setup ("Hey Siri, run a speed test in NetScope").

/// Reads the most recent saved result straight from the app's history file (the same
/// file HistoryStore writes), so the "last result" intent works without launching the UI.
enum SpeedHistoryFile {
    static var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("speedtest-history.json")
    }
    static func latest() -> SpeedResult? {
        guard let data = try? Data(contentsOf: url),
              let rows = try? JSONDecoder().decode([SpeedResult].self, from: data) else { return nil }
        return rows.max(by: { $0.date < $1.date })
    }
}

/// Flag the Speed view checks on appear to auto-start a test launched from Siri.
let kSiriRunFlag = "siriRunSpeedTest"

struct RunSpeedTestIntent: AppIntent {
    static var title: LocalizedStringResource = "Run Speed Test"
    static var description = IntentDescription("Open NetScope and start an internet speed test.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(true, forKey: kSiriRunFlag)
        return .result()
    }
}

struct LastSpeedTestIntent: AppIntent {
    static var title: LocalizedStringResource = "Last Speed Test Result"
    static var description = IntentDescription("Report the most recent NetScope speed-test result.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        guard let r = SpeedHistoryFile.latest() else {
            let none = "You haven't run a speed test in NetScope yet."
            return .result(value: none, dialog: IntentDialog(stringLiteral: none))
        }
        let down = formatSpeed(r.downloadMbps)
        let up = formatSpeed(max(0, r.uploadMbps))
        let ping = Int(r.pingMs.rounded())
        let spoken = "Your last NetScope test: \(down) megabits down, \(up) up, \(ping) milliseconds ping."
        return .result(value: spoken, dialog: IntentDialog(stringLiteral: spoken))
    }

    private func formatSpeed(_ v: Double) -> String {
        v >= 100 ? String(Int(v.rounded())) : String(format: "%.1f", v)
    }
}

struct NetScopeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RunSpeedTestIntent(),
            phrases: [
                "Run a speed test in \(.applicationName)",
                "Test my internet speed with \(.applicationName)",
                "Start a \(.applicationName) speed test",
            ],
            shortTitle: "Run Speed Test",
            systemImageName: "speedometer")
        AppShortcut(
            intent: LastSpeedTestIntent(),
            phrases: [
                "What was my last \(.applicationName) result",
                "Show my last \(.applicationName) speed test",
                "How fast is my internet in \(.applicationName)",
            ],
            shortTitle: "Last Result",
            systemImageName: "clock.arrow.circlepath")
    }
}
