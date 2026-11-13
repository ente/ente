import CoreGraphics
import XCTest
@testable import VideoEditorCore

final class VideoTransformPlannerTests: XCTestCase {
    func testClockwiseQuarterTurnProducesNormalizedPortraitBounds() throws {
        let sourceBounds = CGRect(x: 0, y: 0, width: 320, height: 180)
        let plan = try VideoTransformPlanner.makePlan(
            naturalSize: sourceBounds.size,
            preferredTransform: .identity,
            crop: nil,
            rotateDegrees: 90
        )

        assertEqual(plan.renderSize, CGSize(width: 180, height: 320))
        assertEqual(sourceBounds.applying(plan.transform), CGRect(origin: .zero, size: plan.renderSize))
    }

    func testSpeedOnlyExportNormalizesMetadataRotation() throws {
        let sourceBounds = CGRect(x: 0, y: 0, width: 1080, height: 1920)
        let plan = try VideoTransformPlanner.makePlan(
            naturalSize: sourceBounds.size,
            preferredTransform: CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 0),
            crop: nil,
            rotateDegrees: nil
        )

        assertEqual(plan.renderSize, CGSize(width: 1920, height: 1080))
        assertEqual(sourceBounds.applying(plan.transform), CGRect(origin: .zero, size: plan.renderSize))
    }

    func testCropMapsDisplayRectangleToOutputBounds() throws {
        let crop = try VideoCrop(x: 20, y: 30, width: 100, height: 60)
        let plan = try VideoTransformPlanner.makePlan(
            naturalSize: CGSize(width: 320, height: 180),
            preferredTransform: .identity,
            crop: crop,
            rotateDegrees: 0
        )

        assertEqual(plan.renderSize, CGSize(width: 100, height: 60))
        assertEqual(
            CGRect(x: 20, y: 30, width: 100, height: 60).applying(plan.transform),
            CGRect(origin: .zero, size: plan.renderSize)
        )
    }

    func testDisplaySpaceCropRespectsMetadataRotation() throws {
        let portraitTransform = CGAffineTransform(
            a: 0,
            b: 1,
            c: -1,
            d: 0,
            tx: 180,
            ty: 0
        )
        let crop = try VideoCrop(x: 20, y: 30, width: 80, height: 120)
        let plan = try VideoTransformPlanner.makePlan(
            naturalSize: CGSize(width: 320, height: 180),
            preferredTransform: portraitTransform,
            crop: crop,
            rotateDegrees: 0
        )

        assertEqual(plan.renderSize, CGSize(width: 80, height: 120))
    }

    private func assertEqual(
        _ actual: CGSize,
        _ expected: CGSize,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.width, expected.width, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: 0.001, file: file, line: line)
    }

    private func assertEqual(
        _ actual: CGRect,
        _ expected: CGRect,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: 0.001, file: file, line: line)
    }
}
