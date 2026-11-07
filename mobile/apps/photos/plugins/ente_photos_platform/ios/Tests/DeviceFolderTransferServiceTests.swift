import Photos
@testable import PhotosPlatformCore
import XCTest

final class DeviceFolderTransferServiceTests: XCTestCase {
    func testAlbumActionsRequireFullPhotoAccess() {
        for status: PHAuthorizationStatus in [.notDetermined, .restricted, .denied, .limited] {
            let service = DeviceFolderTransferService(authorizationStatus: { status })
            XCTAssertTrue(service.supportedOperations(sourceFolderID: nil).isEmpty)
            for operation in ["add", "move"] {
                XCTAssertTrue(service.eligibleDestinationIDs(
                    operation: operation, sourceFolderID: nil, candidateIDs: ["target"]
                ).isEmpty)
                let result = service.transfer(
                    operation: operation, sourceFolderID: nil,
                    targetFolderID: "target", sourceLocalIDs: ["photo", "video"]
                )
                XCTAssertTrue(result.destinations.isEmpty)
                XCTAssertEqual(result.failures, ["photo": "permissionDenied", "video": "permissionDenied"])
            }
        }
        let service = DeviceFolderTransferService(authorizationStatus: { .authorized })
        XCTAssertEqual(service.supportedOperations(sourceFolderID: nil), ["add"])
    }
}
