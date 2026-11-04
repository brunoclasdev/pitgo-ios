import Foundation
import CryptoKit
import UIKit

enum GuinchoInspectionCaptureRecoveryError: Error {
    case originalUnavailable(PendingGuinchoInspectionCapture)
    case integrityMismatch(PendingGuinchoInspectionCapture)
}

struct PendingGuinchoInspectionCapture: Codable {
    let captureID: UUID
    let accountID: UUID
    let appointmentID: UUID
    let versionID: UUID
    let point: GuinchoInspectionPoint
    let detailPoint: String?
    let caption: String?
    let replacingPhotoID: UUID?
    let capturedAt: Date
    let reserveOperationID: UUID
    let confirmOperationID: UUID
    var discardOperationID: UUID? = nil
    let originalFilename: String
    let thumbnailFilename: String
    var originalSHA256: String? = nil
    var originalByteSize: Int64? = nil
    var thumbnailSHA256: String? = nil
    var thumbnailByteSize: Int64? = nil
}

final class GuinchoInspectionCaptureStore {
    static let shared = GuinchoInspectionCaptureStore()
    private let fileManager = FileManager.default
    private let rootDirectory: URL?

    init(rootDirectory: URL? = nil) { self.rootDirectory = rootDirectory }

    private func directory(accountID: UUID, appointmentID: UUID) throws -> URL {
        let root = try rootDirectory ?? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let base = root.appendingPathComponent("GuinchoInspectionPending", isDirectory: true)
            .appendingPathComponent(accountID.uuidString, isDirectory: true)
            .appendingPathComponent(appointmentID.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = base
        try? mutable.setResourceValues(values)
        return base
    }

    func save(_ item: PendingGuinchoInspectionCapture, original: Data, thumbnail: Data) throws {
        let folder = try directory(accountID: item.accountID, appointmentID: item.appointmentID)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        // Write the manifest first so a process interruption during either asset write leaves
        // enough metadata to reconcile or discard the capture on the next launch.
        try updateManifest(item, in: folder, encoder: encoder)
        try original.write(to: folder.appendingPathComponent(item.originalFilename), options: .atomic)
        try thumbnail.write(to: folder.appendingPathComponent(item.thumbnailFilename), options: .atomic)
    }

    func updateManifest(_ item: PendingGuinchoInspectionCapture) throws {
        let folder = try directory(accountID: item.accountID, appointmentID: item.appointmentID)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        try updateManifest(item, in: folder, encoder: encoder)
    }

    private func updateManifest(_ item: PendingGuinchoInspectionCapture, in folder: URL, encoder: JSONEncoder) throws {
        let manifest = try encoder.encode(item)
        try manifest.write(to: folder.appendingPathComponent("\(item.captureID.uuidString).json"), options: .atomic)
    }

    func load(accountID: UUID, appointmentID: UUID) throws -> (PendingGuinchoInspectionCapture, Data, Data)? {
        let folder = try directory(accountID: accountID, appointmentID: appointmentID)
        let files = try fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard let manifestURL = files.first else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let milliseconds = try? container.decode(Double.self) { return Date(timeIntervalSince1970: milliseconds / 1000) }
            let text = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: text) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid capture date")
        }
        var item = try decoder.decode(PendingGuinchoInspectionCapture.self, from: Data(contentsOf: manifestURL))
        let originalURL = folder.appendingPathComponent(item.originalFilename)
        guard let original = try? Data(contentsOf: originalURL), UIImage(data: original) != nil else {
            throw GuinchoInspectionCaptureRecoveryError.originalUnavailable(item)
        }
        guard let expectedOriginalHash = item.originalSHA256, let expectedOriginalSize = item.originalByteSize else {
            throw GuinchoInspectionCaptureRecoveryError.integrityMismatch(item)
        }
        guard Int64(original.count) == expectedOriginalSize, Self.sha256(original) == expectedOriginalHash else {
            throw GuinchoInspectionCaptureRecoveryError.integrityMismatch(item)
        }
        // The previous iOS encoder could persist oversized assets, but capture() rejected
        // them before reserving anything remotely. Repair only those never-uploadable bytes.
        if original.count > GuinchoInspectionImageEncoder.originalByteLimit || (item.thumbnailByteSize ?? 0) > GuinchoInspectionImageEncoder.thumbnailByteLimit {
            guard let image = UIImage(data: original), let repaired = GuinchoInspectionImageEncoder.prepare(image) else {
                throw GuinchoInspectionCaptureRecoveryError.originalUnavailable(item)
            }
            item.originalSHA256 = Self.sha256(repaired.original)
            item.originalByteSize = Int64(repaired.original.count)
            item.thumbnailSHA256 = Self.sha256(repaired.thumbnail)
            item.thumbnailByteSize = Int64(repaired.thumbnail.count)
            try save(item, original: repaired.original, thumbnail: repaired.thumbnail)
            return (item, repaired.original, repaired.thumbnail)
        }
        let thumbnailURL = folder.appendingPathComponent(item.thumbnailFilename)
        var thumbnail = try? Data(contentsOf: thumbnailURL)
        if thumbnail.flatMap({ UIImage(data: $0) }) == nil
            || thumbnail.map({ Self.sha256($0) }) != item.thumbnailSHA256
            || thumbnail.map({ Int64($0.count) }) != item.thumbnailByteSize {
            guard let image = UIImage(data: original),
                  let regenerated = [GuinchoInspectionImageEncoder.thumbnail(from: image), Self.thumbnailJPEG(image)]
                    .compactMap({ $0 }).first(where: { Self.sha256($0) == item.thumbnailSHA256 && Int64($0.count) == item.thumbnailByteSize }) else {
                throw GuinchoInspectionCaptureRecoveryError.originalUnavailable(item)
            }
            guard let expectedThumbnailHash = item.thumbnailSHA256,
                  let expectedThumbnailSize = item.thumbnailByteSize,
                  Int64(regenerated.count) == expectedThumbnailSize,
                  Self.sha256(regenerated) == expectedThumbnailHash else {
                throw GuinchoInspectionCaptureRecoveryError.integrityMismatch(item)
            }
            thumbnail = regenerated
            try? regenerated.write(to: thumbnailURL, options: .atomic)
        }
        guard let thumbnail else { throw GuinchoInspectionCaptureRecoveryError.originalUnavailable(item) }
        return (item, original, thumbnail)
    }

    private static func thumbnailJPEG(_ image: UIImage) -> Data? {
        let maxDimension: CGFloat = 900
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.jpegData(withCompressionQuality: 0.58) { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func remove(_ item: PendingGuinchoInspectionCapture) {
        guard let folder = try? directory(accountID: item.accountID, appointmentID: item.appointmentID) else { return }
        for name in [item.originalFilename, item.thumbnailFilename, "\(item.captureID.uuidString).json"] {
            try? fileManager.removeItem(at: folder.appendingPathComponent(name))
        }
    }
}
