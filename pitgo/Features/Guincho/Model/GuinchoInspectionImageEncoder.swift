import UIKit

/// Android inspection limits: normalized JPEG <= 2560px / 5 MiB, thumbnail <= 480px / 256 KiB.
enum GuinchoInspectionImageEncoder {
    static let originalByteLimit = 5_242_880
    static let thumbnailByteLimit = 262_144

    struct Images {
        let original: Data
        let thumbnail: Data
    }

    static func prepare(_ image: UIImage) -> Images? {
        guard let normalized = render(image, maxDimension: 2560),
              let thumbnail = render(normalized, maxDimension: 480),
              let originalBytes = jpeg(normalized, byteLimit: originalByteLimit),
              let thumbnailBytes = jpeg(thumbnail, byteLimit: thumbnailByteLimit) else { return nil }
        return Images(original: originalBytes, thumbnail: thumbnailBytes)
    }

    static func thumbnail(from image: UIImage) -> Data? {
        guard let thumbnail = render(image, maxDimension: 480) else { return nil }
        return jpeg(thumbnail, byteLimit: thumbnailByteLimit)
    }

    private static func render(_ image: UIImage, maxDimension: CGFloat) -> UIImage? {
        let width = image.size.width * image.scale
        let height = image.size.height * image.scale
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return nil }
        let ratio = min(1, maxDimension / max(width, height))
        let size = CGSize(width: max(1, floor(width * ratio)), height: max(1, floor(height * ratio)))
        let format = UIGraphicsImageRendererFormat()
        // Pixels must not depend on the phone's @2x/@3x display scale.
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private static func jpeg(_ image: UIImage, byteLimit: Int) -> Data? {
        for quality: CGFloat in [0.90, 0.80, 0.65, 0.50] {
            if let bytes = image.jpegData(compressionQuality: quality), (1...byteLimit).contains(bytes.count) { return bytes }
        }
        return nil
    }
}
