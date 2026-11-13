import CoreGraphics

public struct VideoTransformPlan: Sendable {
    public let transform: CGAffineTransform
    public let renderSize: CGSize
}

public enum VideoTransformPlanner {
    public static func makePlan(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        crop: VideoCrop?,
        rotateDegrees: Int?
    ) throws -> VideoTransformPlan {
        if let crop {
            return try cropPlan(
                naturalSize: naturalSize,
                preferredTransform: preferredTransform,
                crop: crop,
                rotateDegrees: rotateDegrees ?? 0
            )
        }
        return rotationPlan(
            naturalSize: naturalSize,
            preferredTransform: preferredTransform,
            rotateDegrees: rotateDegrees ?? 0
        )
    }

    private static func cropPlan(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        crop: VideoCrop,
        rotateDegrees: Int
    ) throws -> VideoTransformPlan {
        let normalizedRotation = ((rotateDegrees % 360) + 360) % 360
        let naturalBounds = CGRect(origin: .zero, size: naturalSize)
        let preferredBounds = naturalBounds.applying(preferredTransform)
        let orientationAdjustment = CGAffineTransform(
            translationX: -preferredBounds.minX,
            y: -preferredBounds.minY
        )
        let orientationTransform = preferredTransform.concatenating(orientationAdjustment)
        guard orientationTransform.isNearlyInvertible else {
            throw VideoEditorError.export("Invalid orientation transform during crop")
        }

        let cropRectDisplay = CGRect(
            x: CGFloat(crop.x),
            y: CGFloat(crop.y),
            width: CGFloat(crop.width),
            height: CGFloat(crop.height)
        )
        let displayBounds = CGRect(
            origin: .zero,
            size: CGSize(
                width: abs(preferredBounds.width),
                height: abs(preferredBounds.height)
            )
        )
        let tolerance: CGFloat = 0.5
        guard cropRectDisplay.minX >= displayBounds.minX - tolerance,
            cropRectDisplay.minY >= displayBounds.minY - tolerance,
            cropRectDisplay.maxX <= displayBounds.maxX + tolerance,
            cropRectDisplay.maxY <= displayBounds.maxY + tolerance
        else {
            throw VideoEditorError.export("Crop rectangle exceeds the displayed video")
        }

        let displayCorners = [
            cropRectDisplay.origin,
            CGPoint(x: cropRectDisplay.maxX, y: cropRectDisplay.minY),
            CGPoint(x: cropRectDisplay.minX, y: cropRectDisplay.maxY),
            CGPoint(x: cropRectDisplay.maxX, y: cropRectDisplay.maxY),
        ]
        let orientationInverse = orientationTransform.inverted()
        let fileCorners = displayCorners.map { $0.applying(orientationInverse) }
        let fileMinX = fileCorners.map(\.x).min() ?? 0
        let fileMinY = fileCorners.map(\.y).min() ?? 0
        let fileMaxX = fileCorners.map(\.x).max() ?? 0
        let fileMaxY = fileCorners.map(\.y).max() ?? 0
        let fileCropRect = CGRect(
            x: fileMinX,
            y: fileMinY,
            width: fileMaxX - fileMinX,
            height: fileMaxY - fileMinY
        )

        var transform = CGAffineTransform(
            translationX: -fileCropRect.origin.x,
            y: -fileCropRect.origin.y
        ).concatenating(orientationTransform)
        if normalizedRotation != 0 {
            let clockwiseRadians = CGFloat(normalizedRotation) * .pi / 180
            transform = transform.concatenating(
                CGAffineTransform(rotationAngle: clockwiseRadians)
            )
        }

        let transformedCorners = fileCorners.map { $0.applying(transform) }
        let minX = transformedCorners.map(\.x).min() ?? 0
        let minY = transformedCorners.map(\.y).min() ?? 0
        let maxX = transformedCorners.map(\.x).max() ?? 0
        let maxY = transformedCorners.map(\.y).max() ?? 0
        transform = transform.concatenating(
            CGAffineTransform(translationX: -minX, y: -minY)
        )

        return VideoTransformPlan(
            transform: transform,
            renderSize: CGSize(
                width: max((maxX - minX).rounded(), 1),
                height: max((maxY - minY).rounded(), 1)
            )
        )
    }

    private static func rotationPlan(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        rotateDegrees: Int
    ) -> VideoTransformPlan {
        let naturalBounds = CGRect(origin: .zero, size: naturalSize)
        let preferredBounds = naturalBounds.applying(preferredTransform)
        let orientationAdjustment = CGAffineTransform(
            translationX: -preferredBounds.minX,
            y: -preferredBounds.minY
        )
        let orientationTransform = preferredTransform.concatenating(orientationAdjustment)
        let orientedSize = CGSize(
            width: abs(preferredBounds.width),
            height: abs(preferredBounds.height)
        )
        let clockwiseRadians = CGFloat(rotateDegrees) * .pi / 180
        let centerX = orientedSize.width / 2
        let centerY = orientedSize.height / 2

        var transform = orientationTransform
        transform = transform.translatedBy(x: centerX, y: centerY)
        transform = transform.rotated(by: clockwiseRadians)
        transform = transform.translatedBy(x: -centerX, y: -centerY)

        let transformedBounds = naturalBounds.applying(transform)
        let renderSize = CGSize(
            width: abs(transformedBounds.width),
            height: abs(transformedBounds.height)
        )
        let targetMinX = (renderSize.width - transformedBounds.width) / 2
        let targetMinY = (renderSize.height - transformedBounds.height) / 2
        transform = transform.concatenating(
            CGAffineTransform(
                translationX: targetMinX - transformedBounds.minX,
                y: targetMinY - transformedBounds.minY
            )
        )
        return VideoTransformPlan(transform: transform, renderSize: renderSize)
    }
}

private extension CGAffineTransform {
    var isNearlyInvertible: Bool {
        abs((a * d) - (b * c)) > 1e-8
    }
}
