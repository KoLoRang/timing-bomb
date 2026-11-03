import SwiftUI
import TimingBombL10n

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppearanceMode.apply(AppearanceMode.stored)
        AppNativeNotificationPresenter.shared.start()
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
                .frame(minWidth: AppLayout.windowMinWidth, minHeight: 700)
        }
        .defaultSize(width: 1320, height: 820)
        .windowResizability(.contentMinSize)
    }
}

struct MainSidebarView: View {
    enum Page: String, Hashable, CaseIterable, Identifiable {
        case flows
        case favorites
        case approvals
        case runs
        case settings

        var id: String { rawValue }

        var label: String {
            switch self {
            case .flows: return L10n.t("Flows")
            case .favorites: return L10n.t("Favorite Nodes")
            case .approvals: return L10n.t("Approvals")
            case .runs: return L10n.t("Runs")
            case .settings: return L10n.t("Settings")
            }
        }

        var icon: String {
            switch self {
            case .flows: return "square.3.layers.3d.top.filled"
            case .favorites: return "star"
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
            // Plain VStack, not a ScrollView: inside the sidebar a ScrollView's
            // titlebar content inset shifts hit-testing away from the drawn rows.
            VStack(spacing: 4) {
                ForEach(Page.allCases) { item in
                    SidebarRow(item: item, selected: (page ?? .flows) == item) {
                        page = item
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // Fixed width: the sidebar must never be squeezed by a wide detail page,
            // otherwise its contents shift whenever the selected page changes.
            .navigationSplitViewColumnWidth(AppLayout.sidebarWidth)
        } detail: {
            switch page {
            case .flows: FlowsView()
            case .favorites: FavoriteNodesView()
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

private struct SidebarRow: View {
    let item: MainSidebarView.Page
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: item.icon)
                    .font(.system(size: 14))
                    .frame(width: 20)
                    .foregroundStyle(selected ? Color.white : Color.accentColor)
                Text(item.label)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.white : Color.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected
                        ? Color.accentColor
                        : (hovering ? Color.primary.opacity(0.06) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
