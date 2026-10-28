import AppKit
import TimingBombL10n

/// Menu bar resident icon: service status, start/stop, open main window, quit.
final class StatusBarManager: NSObject, NSMenuDelegate {
    static let shared = StatusBarManager()

    private var statusItem: NSStatusItem?

    func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = Self.loadIcon()
        }
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        statusItem = item
    }

    /// NSImage(named:) does not pick up @2x variants of loose files; load @2x directly for Retina.
    static func loadIcon() -> NSImage? {
        let candidates = [
            "MenuBarTemplate@2x", "MenuBarTemplate", "MenuBar16Template@2x", "MenuBar16Template",
        ]
        var image = candidates.lazy.compactMap { NSImage(named: $0) }.first
        if image == nil {
            image = NSImage(systemSymbolName: "timer", accessibilityDescription: "TimingBomb")
        }
        image?.isTemplate = true
        image?.size = NSSize(width: 18, height: 18)
        return image
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        MainActor.assumeIsolated {
            rebuild(menu)
        }
    }

    @MainActor
    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()
        let daemon = DaemonManager.shared

        let statusTitle: String
        switch daemon.state {
        case .running:
            statusTitle = "● "
                + L10n.t("Service running")
                + (daemon.daemonVersion.map { " · v\($0)" } ?? "")
        case .stopped:
            statusTitle = "○ " + L10n.t("Service stopped")
        case .checking:
            statusTitle = "… " + L10n.t("Checking service state")
        }
        menu.addItem(disabledItem(statusTitle))

        switch daemon.state {
        case .running:
            menu.addItem(
                actionItem(L10n.t("Stop Service")) {
                    Task { @MainActor in DaemonManager.shared.stopDaemon() }
                })
        case .stopped:
            menu.addItem(
                actionItem(L10n.t("Start Service")) {
                    Task { @MainActor in DaemonManager.shared.startDaemon() }
                })
        case .checking:
            break
        }

        menu.addItem(.separator())
        menu.addItem(
            actionItem(L10n.t("Open Main Window")) {
                NSApp.activate(ignoringOtherApps: true)
                WindowOpener.open?()
            })

        menu.addItem(.separator())
        menu.addItem(
            actionItem(L10n.t("Quit TimingBomb (service keeps running)")) {
                NSApp.terminate(nil)
            })
        menu.addItem(
            actionItem(L10n.t("Quit and Stop Service")) {
                Task { @MainActor in
                    DaemonManager.shared.stopDaemon()
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    NSApp.terminate(nil)
                }
            })
    }

    // MARK: Items

    private final class ActionMenuItem: NSMenuItem {
        var handler: (() -> Void)?
    }

    @objc private func performAction(_ sender: NSMenuItem) {
        (sender as? ActionMenuItem)?.handler?()
    }

    private func actionItem(_ title: String, handler: @escaping () -> Void) -> NSMenuItem {
        let item = ActionMenuItem(
            title: title, action: #selector(performAction(_:)), keyEquivalent: "")
        item.target = self
        item.handler = handler
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(
            title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }
}

/// Lets AppKit menu callbacks reopen the SwiftUI main window.
enum WindowOpener {
    static var open: (() -> Void)?
}
