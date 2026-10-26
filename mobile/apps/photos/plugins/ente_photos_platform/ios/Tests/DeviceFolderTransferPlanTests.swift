@testable import PhotosPlatformCore
import XCTest

final class DeviceFolderTransferPlanTests: XCTestCase {
    func testAddIncludesOnlyAccessibleNewMembersAndKeepsExistingMemberships() {
        let plan = DeviceFolderTransferPlan(
            requestedIDs: ["photo", "video", "missing"], accessibleIDs: ["photo", "video"],
            sourceMemberIDs: nil, targetMemberIDs: ["video"]
        )
        XCTAssertEqual(plan.addedIDs, ["photo"])
        XCTAssertEqual(plan.completedIDs, ["photo", "video"])
        XCTAssertEqual(plan.missingIDs, ["missing"])
        XCTAssertTrue(plan.removedIDs.isEmpty)
    }

    func testMoveRemovesOnlyAccessibleSourceMembers() {
        let plan = DeviceFolderTransferPlan(
            requestedIDs: ["photo", "video", "missing", "elsewhere"],
            accessibleIDs: ["photo", "video", "elsewhere"],
            sourceMemberIDs: ["photo", "video", "missing"], targetMemberIDs: ["video"]
        )
        XCTAssertEqual(plan.addedIDs, ["photo"])
        XCTAssertEqual(plan.removedIDs, ["photo", "video"])
        XCTAssertEqual(plan.completedIDs, ["photo", "video"])
        XCTAssertEqual(plan.missingIDs, ["missing", "elsewhere"])
    }
}
