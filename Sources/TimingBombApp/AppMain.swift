import SwiftUI
import TimingBombL10n

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppearanceMode.apply(AppearanceMode.stored)
        DaemonManager.shared.startLifecycle()
        StatusBarManager.shared.install()

        // The green button only zooms, never fullscreen — the three-pane layout looks bad fullscreen.
        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeMainNotification, object: nil, queue: .main
        ) { note in
            if let window = note.object as? NSWindow {
                window.collectionBehavior.insert(.fullScreenNone)
            }
        }
    }
}

@main
struct TimingBombApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("TimingBomb", id: "main") {
            MainSidebarView()
                // The min size must fit the tallest sheet (node editor), otherwise
                // the bottom buttons get clipped on create/edit.
                .frame(minWidth: 1060, minHeight: 700)
        }
        .defaultSize(width: 1280, height: 800)
        .windowResizability(.contentMinSize)
    }
}

struct MainSidebarView: View {
    enum Page: String, Hashable, CaseIterable, Identifiable {
        case flows
        case approvals
        case runs
        case settings

        var id: String { rawValue }

        var label: String {
            switch self {
            case .flows: return L10n.t("Flows")
            case .approvals: return L10n.t("Approvals")
            case .runs: return L10n.t("Runs")
            case .settings: return L10n.t("Settings")
            }
        }

        var icon: String {
            switch self {
            case .flows: return "square.3.layers.3d.top.filled"
            case .approvals: return "checkmark.seal"
            case .runs: return "doc.text.magnifyingglass"
            case .settings: return "gearshape"
            }
        }
    }

    @State private var page: Page? = MainSidebarView.startPage
    @Environment(\.openWindow) private var openWindow

    /// Re-evaluates when the `TB_LANG` override changes (written by the
    /// Settings language picker); `.id` below rebuilds the page tree so every
    /// L10n.t call re-renders in the new language.
    @AppStorage("TB_LANG") private var languageOverride = ""

    /// Test hook: `TB_START_PAGE=flows|approvals|runs|settings` opens a specific page (GUI smoke tests).
    static var startPage: Page {
        switch ProcessInfo.processInfo.environment["TB_START_PAGE"] {
        case "approvals": return .approvals
        case "runs": return .runs
        case "settings": return .settings
        default: return .flows
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $page) {
                ForEach(Page.allCases) { item in
                    Label(item.label, systemImage: item.icon)
                        .tag(item)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        } detail: {
            switch page {
            case .flows: FlowsView()
            case .approvals: ApprovalsView()
            case .runs: RunsView()
            case .settings: SettingsView()
            case nil: FlowsView()
            }
        }
        .id(languageOverride)
        .onAppear {
            WindowOpener.open = { openWindow(id: "main") }
        }
    }
}
