import UIKit
import Foundation

@main struct GuinchoInspectionImageRegression {
    @MainActor static func main() throws {
        // A high-entropy @3x camera image catches the old renderer's device-scale multiplication.
        let width = 3200, height = 2400
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        var seed: UInt32 = 123456
        for index in stride(from: 0, to: pixels.count, by: 4) {
            for channel in 0..<3 {
                seed = seed &* 1664525 &+ 1013904223
                pixels[index + channel] = UInt8(truncatingIfNeeded: seed >> 16)
            }
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let bitmap = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
        let source = UIImage(cgImage: bitmap, scale: 3, orientation: .right)
        let prepared = GuinchoInspectionImageEncoder.prepare(source)!
        let original = UIImage(data: prepared.original)!, thumbnail = UIImage(data: prepared.thumbnail)!
        precondition(max(original.cgImage!.width, original.cgImage!.height) == 2560)
        precondition(max(thumbnail.cgImage!.width, thumbnail.cgImage!.height) == 480)
        precondition(prepared.original.count <= 5_242_880 && prepared.thumbnail.count <= 262_144)
        precondition(original.imageOrientation == .up && thumbnail.imageOrientation == .up)

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("inspection-image-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = GuinchoInspectionCaptureStore(rootDirectory: root)
        let accountID = UUID(), appointmentID = UUID(), captureID = UUID()
        let date = Date(timeIntervalSince1970: 1_794_000_000.123456)
        var item = PendingGuinchoInspectionCapture(captureID: captureID, accountID: accountID, appointmentID: appointmentID,
            versionID: UUID(), point: .front, detailPoint: nil, caption: nil, replacingPhotoID: nil, capturedAt: date,
            reserveOperationID: UUID(), confirmOperationID: UUID(), originalFilename: "original.jpg", thumbnailFilename: "thumbnail.jpg",
            originalSHA256: GuinchoInspectionCaptureStore.sha256(prepared.original), originalByteSize: Int64(prepared.original.count),
            thumbnailSHA256: GuinchoInspectionCaptureStore.sha256(prepared.thumbnail), thumbnailByteSize: Int64(prepared.thumbnail.count))
        try store.save(item, original: prepared.original, thumbnail: prepared.thumbnail)
        let loaded = try store.load(accountID: accountID, appointmentID: appointmentID)!
        let style = Date.ISO8601FormatStyle().year().month().day().dateTimeSeparator(.standard).time(includingFractionalSeconds: true)
        precondition(date.formatted(style) == loaded.0.capturedAt.formatted(style))
        precondition(loaded.1 == prepared.original && loaded.2 == prepared.thumbnail)

        // Old persisted assets that were rejected locally must recover without a new operation ID.
        let oversized = prepared.thumbnail + Data(repeating: 0, count: 262_145)
        item.thumbnailSHA256 = GuinchoInspectionCaptureStore.sha256(oversized)
        item.thumbnailByteSize = Int64(oversized.count)
        try store.save(item, original: prepared.original, thumbnail: oversized)
        let repaired = try store.load(accountID: accountID, appointmentID: appointmentID)!
        precondition(repaired.0.reserveOperationID == item.reserveOperationID && repaired.0.confirmOperationID == item.confirmOperationID)
        precondition(repaired.1.count <= 5_242_880 && repaired.2.count <= 262_144)
        precondition(GuinchoInspectionCaptureStore.sha256(repaired.2) == repaired.0.thumbnailSHA256)

        // Backward-compatible read of existing ISO8601 manifests.
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let folder = root.appendingPathComponent("GuinchoInspectionPending/\(accountID.uuidString)/\(appointmentID.uuidString)")
        try encoder.encode(repaired.0).write(to: folder.appendingPathComponent("\(captureID.uuidString).json"))
        let legacy = try store.load(accountID: accountID, appointmentID: appointmentID)!
        precondition(legacy.0.captureID == captureID)
        print("PASS: @3x image pixels, rotation, JPEG/thumbnail budgets, capture timestamp persistence, oversized pending repair and legacy manifests")
    }
}
