import AppKit
import Combine
import SwiftUI

@main
struct CodexMeterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private lazy var store = UsageStore(previewMode: ProcessInfo.processInfo.arguments.contains("--preview"))
    private let popover = NSPopover()
    private var statusItem: NSStatusItem!
    private var cancellables = Set<AnyCancellable>()
    private var previewWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let previewMode = ProcessInfo.processInfo.arguments.contains("--preview")
        NSApp.setActivationPolicy(previewMode ? .regular : .accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "gauge", accessibilityDescription: "Codex usage")
            button.imagePosition = .imageLeading
            button.title = "—"
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.target = self
            button.action = #selector(togglePopover)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: MeterView(store: store))

        if previewMode {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 348, height: 500),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Codex Meter"
            window.contentViewController = NSHostingController(rootView: MeterView(store: store))
            window.center()
            window.makeKeyAndOrderFront(nil)
            previewWindow = window
            NSApp.activate(ignoringOtherApps: true)
        }

        store.start()
        store.$payload
            .combineLatest(store.$errorMessage)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in self?.updateStatusItem() }
            .store(in: &cancellables)
        updateStatusItem()
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Refresh", action: #selector(refresh), keyEquivalent: "r").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit Codex Meter", action: #selector(quit), keyEquivalent: "q").target = self
            statusItem.menu = menu
            button.performClick(nil)
            statusItem.menu = nil
            return
        }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc private func refresh() { Task { await store.refresh() } }
    @objc private func quit() { NSApp.terminate(nil) }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        if let remaining = store.menuBarRemaining {
            button.title = "\(remaining)%"
            button.toolTip = "Codex: \(remaining)% remaining in the tightest usage window"
        } else {
            button.title = "—"
            if let error = store.errorMessage {
                button.toolTip = "Codex usage unavailable: \(error)"
            } else if store.isStale, let updated = store.payload?.fetchedAt {
                button.toolTip = "Codex usage is out of date. Last updated \(updated.formatted(date: .omitted, time: .shortened))."
            } else {
                button.toolTip = "Checking Codex usage"
            }
        }
        button.setAccessibilityLabel(button.toolTip ?? "Codex usage")
    }
}
