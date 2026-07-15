import AppKit
import Foundation
import ServiceManagement
import UserNotifications

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var payload: RateLimitPayload?
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    @Published var alertThreshold: Int {
        didSet { UserDefaults.standard.set(alertThreshold, forKey: Self.thresholdKey) }
    }
    @Published private(set) var launchAtLogin = false

    private let client = CodexAppServerClient()
    private let previewMode: Bool
    private var pollingTask: Task<Void, Never>?
    private static let thresholdKey = "alertThreshold"
    private static let notifiedResetKey = "lastNotifiedReset"

    init(previewMode: Bool = false) {
        self.previewMode = previewMode
        let saved = UserDefaults.standard.integer(forKey: Self.thresholdKey)
        alertThreshold = saved == 0 ? 20 : saved
        if previewMode {
            let now = Date()
            payload = RateLimitPayload(
                snapshot: RateLimitSnapshot(
                    limitID: "codex",
                    limitName: "Codex",
                    planType: "plus",
                    primary: RateLimitWindow(usedPercent: 58, resetsAt: now.addingTimeInterval(8_040), durationMinutes: 300),
                    secondary: RateLimitWindow(usedPercent: 32, resetsAt: now.addingTimeInterval(403_200), durationMinutes: 10_080)
                ),
                fetchedAt: now
            )
        }
        if #available(macOS 13.0, *) {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    var windows: [RateLimitWindow] { payload?.snapshot.windows ?? [] }
    var menuBarRemaining: Int? {
        guard errorMessage == nil, !isStale else { return nil }
        return payload?.snapshot.mostConstrainedRemaining
    }
    var planLabel: String? {
        payload?.snapshot.planType?.replacingOccurrences(of: "_", with: " ").capitalized
    }
    var isStale: Bool {
        guard let fetchedAt = payload?.fetchedAt else { return false }
        return Date().timeIntervalSince(fetchedAt) > 180
    }

    func start() {
        guard !previewMode else { return }
        pollingTask?.cancel()
        pollingTask = Task {
            await refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(120))
                guard !Task.isCancelled else { break }
                await refresh()
            }
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let newPayload = try await client.readRateLimits()
            payload = newPayload
            errorMessage = newPayload.snapshot.windows.isEmpty ? "No Codex rate-limit windows were returned for this account." : nil
            await notifyIfNeeded(newPayload)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            await client.stop()
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            errorMessage = "Launch at login could not be changed: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func openCodex() {
        let appURL = URL(fileURLWithPath: "/Applications/ChatGPT.app")
        if FileManager.default.fileExists(atPath: appURL.path) {
            NSWorkspace.shared.openApplication(at: appURL, configuration: .init())
        }
    }

    private func notifyIfNeeded(_ payload: RateLimitPayload) async {
        guard let constrained = payload.snapshot.windows.min(by: { $0.remainingPercent < $1.remainingPercent }),
              constrained.remainingPercent <= alertThreshold else { return }

        let resetID = String(Int(constrained.resetsAt?.timeIntervalSince1970 ?? 0))
        guard UserDefaults.standard.string(forKey: Self.notifiedResetKey) != resetID else { return }

        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return }

        let content = UNMutableNotificationContent()
        content.title = "Codex usage is running low"
        content.body = "\(constrained.remainingPercent)% remains. \(ResetTimeFormatter.notificationText(for: constrained.resetsAt))"
        content.sound = .default
        try? await center.add(UNNotificationRequest(identifier: "codex-meter-low-\(resetID)", content: content, trigger: nil))
        UserDefaults.standard.set(resetID, forKey: Self.notifiedResetKey)
    }
}

enum ResetTimeFormatter {
    static func relativeText(for date: Date?, now: Date = Date()) -> String {
        guard let date else { return "Reset time unavailable" }
        if date <= now { return "Resetting now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Resets \(formatter.localizedString(for: date, relativeTo: now))"
    }

    static func absoluteText(for date: Date?) -> String? {
        guard let date else { return nil }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    static func notificationText(for date: Date?) -> String {
        guard let date else { return "The reset time is unavailable." }
        return "It resets \(date.formatted(date: .omitted, time: .shortened))."
    }
}
