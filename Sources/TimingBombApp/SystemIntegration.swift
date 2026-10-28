import Foundation
import ServiceManagement
import TimingBombL10n

/// Launch-at-login toggle (SMAppService login item). Not registered after install;
/// only written to the system login items when the user flips the switch in Settings.
@MainActor
final class LoginItemManager: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var statusText = L10n.t("Not enabled")
    @Published private(set) var lastError: String?

    init() {
        refresh()
    }

    func refresh() {
        switch SMAppService.mainApp.status {
        case .enabled:
            enabled = true
            statusText = L10n.t("Enabled · TimingBomb opens and starts the service at login")
        case .requiresApproval:
            enabled = false
            statusText = L10n.t("Awaiting approval · allow TimingBomb in System Settings → General → Login Items")
        case .notRegistered:
            enabled = false
            statusText = L10n.t("Not enabled")
        case .notFound:
            enabled = false
            statusText = L10n.t("App not found; make sure TimingBomb.app was not moved")
        @unknown default:
            enabled = false
            statusText = L10n.t("Unknown state")
        }
    }

    func setEnabled(_ on: Bool) {
        lastError = nil
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            lastError = L10n.t("Setting failed: {detail}", ["detail": error.localizedDescription])
        }
        refresh()
    }
}

