import Combine
import ServiceManagement

protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginItemService {}

final class LoginItemController: ObservableObject {
    @Published private(set) var status: SMAppService.Status
    @Published private(set) var error: String?
    private let service: LoginItemService
    private let showSystemSettings: () -> Void

    // macOS owns this preference, so changes made in System Settings remain authoritative.
    var isRegistered: Bool { status == .enabled || status == .requiresApproval }
    var needsApproval: Bool { status == .requiresApproval }
    var isUnavailable: Bool { status == .notFound }

    init(service: LoginItemService = SMAppService.mainApp,
         showSystemSettings: @escaping () -> Void = SMAppService.openSystemSettingsLoginItems) {
        self.service = service
        self.showSystemSettings = showSystemSettings
        status = service.status
    }

    func refresh() { status = service.status }

    func setEnabled(_ enabled: Bool) {
        error = nil
        refresh()
        do {
            if enabled && !isRegistered { try service.register() }
            else if !enabled && isRegistered { try service.unregister() }
        } catch {
            self.error = "Couldn’t change open at startup. \(error.localizedDescription)"
        }
        refresh()
    }

    func openSystemSettings() { showSystemSettings() }
}
