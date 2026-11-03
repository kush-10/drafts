import ServiceManagement
import XCTest
@testable import Drafts

private final class TestLoginItemService: LoginItemService {
    var status: SMAppService.Status = .notRegistered
    var registrationStatus: SMAppService.Status = .enabled
    var registrationError: Error?
    var unregistrationError: Error?
    var registrations = 0
    var unregistrations = 0

    func register() throws {
        registrations += 1
        if let registrationError { throw registrationError }
        status = registrationStatus
    }

    func unregister() throws {
        unregistrations += 1
        if let unregistrationError { throw unregistrationError }
        status = .notRegistered
    }
}

final class LoginItemTests: XCTestCase {
    func testOpeningSettingsDoesNotOptInToStartup() {
        let service = TestLoginItemService()
        let controller = LoginItemController(service: service)
        controller.refresh()
        XCTAssertFalse(controller.isRegistered)
        XCTAssertFalse(controller.needsApproval)
        XCTAssertEqual(service.registrations, 0)
        XCTAssertEqual(service.unregistrations, 0)
    }

    func testToggleRegistersAndUnregistersMainApp() {
        let service = TestLoginItemService()
        let controller = LoginItemController(service: service)
        controller.setEnabled(true)
        XCTAssertTrue(controller.isRegistered)
        XCTAssertEqual(controller.status, .enabled)
        XCTAssertNil(controller.error)
        controller.setEnabled(false)
        XCTAssertFalse(controller.isRegistered)
        XCTAssertEqual(service.registrations, 1)
        XCTAssertEqual(service.unregistrations, 1)
    }

    func testApprovalPendingIsVisibleAndCanBeCancelled() {
        let service = TestLoginItemService()
        service.registrationStatus = .requiresApproval
        let controller = LoginItemController(service: service)
        controller.setEnabled(true)
        XCTAssertTrue(controller.isRegistered)
        XCTAssertTrue(controller.needsApproval)
        controller.setEnabled(true)
        XCTAssertEqual(service.registrations, 1, "Pending services must not be registered twice")
        controller.setEnabled(false)
        XCTAssertFalse(controller.isRegistered)
        XCTAssertFalse(controller.needsApproval)
        XCTAssertEqual(service.unregistrations, 1)
    }

    func testExternalChangesAreReflectedWithoutOverridingSystemSettings() {
        let service = TestLoginItemService()
        service.status = .enabled
        let controller = LoginItemController(service: service)
        XCTAssertTrue(controller.isRegistered)
        service.status = .requiresApproval
        controller.refresh()
        XCTAssertTrue(controller.needsApproval)
        service.status = .notRegistered
        controller.refresh()
        XCTAssertFalse(controller.isRegistered)
        XCTAssertEqual(service.registrations, 0)
        XCTAssertEqual(service.unregistrations, 0)
    }

    func testToggleRefreshesStaleStatusAndAvoidsRedundantChanges() {
        let service = TestLoginItemService()
        let controller = LoginItemController(service: service)
        service.status = .enabled
        controller.setEnabled(true)
        XCTAssertTrue(controller.isRegistered)
        XCTAssertEqual(service.registrations, 0)
        service.status = .notRegistered
        controller.setEnabled(false)
        XCTAssertFalse(controller.isRegistered)
        XCTAssertEqual(service.unregistrations, 0)
    }

    func testFailedRegistrationKeepsActualStateAndCanBeRetried() {
        let service = TestLoginItemService()
        service.registrationError = NSError(domain: "LoginItemTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Registration denied"])
        let controller = LoginItemController(service: service)
        controller.setEnabled(true)
        XCTAssertFalse(controller.isRegistered)
        XCTAssertTrue(controller.error?.contains("Registration denied") == true)
        service.registrationError = nil
        controller.setEnabled(true)
        XCTAssertTrue(controller.isRegistered)
        XCTAssertNil(controller.error)
    }

    func testFailedUnregistrationDoesNotPretendStartupIsDisabled() {
        let service = TestLoginItemService()
        service.status = .enabled
        service.unregistrationError = NSError(domain: "LoginItemTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Removal denied"])
        let controller = LoginItemController(service: service)
        controller.setEnabled(false)
        XCTAssertTrue(controller.isRegistered)
        XCTAssertTrue(controller.error?.contains("Removal denied") == true)
        service.unregistrationError = nil
        controller.setEnabled(false)
        XCTAssertFalse(controller.isRegistered)
        XCTAssertNil(controller.error)
    }

    func testMissingRecordCanBeRegisteredOnFirstUse() {
        let service = TestLoginItemService()
        service.status = .notFound
        let controller = LoginItemController(service: service)
        XCTAssertFalse(controller.isRegistered)
        controller.setEnabled(true)
        XCTAssertEqual(service.registrations, 1)
        XCTAssertEqual(controller.status, .enabled)
        XCTAssertTrue(controller.isRegistered)
        XCTAssertNil(controller.error)
        controller.setEnabled(false)
        XCTAssertEqual(service.unregistrations, 1)
        XCTAssertFalse(controller.isRegistered)
    }

    func testApprovalButtonOpensLoginItemsSettings() {
        let service = TestLoginItemService()
        var opened = false
        let controller = LoginItemController(service: service, showSystemSettings: { opened = true })
        controller.openSystemSettings()
        XCTAssertTrue(opened)
        XCTAssertEqual(service.registrations, 0)
    }
}
