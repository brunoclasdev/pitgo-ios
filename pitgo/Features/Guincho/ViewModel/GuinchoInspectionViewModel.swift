import Combine
import Foundation
import UIKit

@MainActor
final class GuinchoInspectionViewModel: ObservableObject {
    @Published private(set) var document: GuinchoInspectionDocument?
    @Published private(set) var photos: [GuinchoInspectionPhoto] = []
    @Published private(set) var images: [UUID: UIImage] = [:]
    @Published private(set) var hasMorePhotos = false
    @Published private(set) var isLoadingMorePhotos = false
    @Published private(set) var enlargedImage: UIImage?
    @Published private(set) var isLoadingEnlargedImage = false
    @Published private(set) var versions: [GuinchoInspectionVersion] = []
    @Published private(set) var versionPhotos: [UUID: [GuinchoInspectionPhoto]] = [:]
    @Published private(set) var hasMoreVersions = false
    @Published private(set) var isLoadingMoreVersions = false
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var failure: String?
    @Published private(set) var submissionConfirmedID: UUID?
    @Published private(set) var hasUnrecoverableCapture = false

    private let appointmentID: UUID
    private let repository: GuinchoInspectionRepository
    private struct PendingCapture {
        let metadata: PendingGuinchoInspectionCapture
        let original: Data
        let thumbnail: Data
    }
    private var pendingCapture: PendingCapture?
    private var unrecoverableCapture: PendingGuinchoInspectionCapture?
    private let captureStore = GuinchoInspectionCaptureStore.shared
    private struct SubmitIntent: Codable {
        let accountID: UUID
        let appointmentID: UUID
        let versionID: UUID
        let operationID: UUID
    }
    private var isSubmittingIntent = false
    private var isCapturePersisted = false
    var hasPendingCapture: Bool { pendingCapture != nil }

    init(appointmentID: UUID, repository: GuinchoInspectionRepository) {
        self.appointmentID = appointmentID
        self.repository = repository
    }

    func load() {
        guard !isLoading else { return }
        isLoading = true
        failure = nil
        Task {
            do {
                document = try await repository.document(appointmentID: appointmentID)
                if let versionID = document?.summary.currentVersionID {
                    let page = try await repository.photos(appointmentID: appointmentID, versionID: versionID)
                    photos = page.items
                    hasMorePhotos = page.hasMore
                    for photo in photos where images[photo.id] == nil {
                        do {
                            let data = try await repository.downloadThumbnail(photo)
                            guard let image = UIImage(data: data) else { throw GuinchoInspectionError.invalidImage }
                            images[photo.id] = image
                        } catch {
                            failure = "Uma ou mais fotos não puderam ser carregadas. Tente novamente antes de aprovar."
                        }
                    }
                    if document?.closed == true {
                        hasMorePhotos = false
                        let versionPage = try await repository.versions(appointmentID: appointmentID)
                        versions = versionPage.items
                        hasMoreVersions = versionPage.hasMore
                        for version in versionPage.items {
                            let allPhotos = try await listAllPhotos(versionID: version.id)
                            versionPhotos[version.id] = allPhotos
                            for photo in allPhotos where images[photo.id] == nil {
                                do {
                                    let data = try await repository.downloadThumbnail(photo)
                                    guard let image = UIImage(data: data) else { throw GuinchoInspectionError.invalidImage }
                                    images[photo.id] = image
                                } catch {
                                    failure = "Uma ou mais fotos históricas não puderam ser carregadas. Tente novamente."
                                }
                            }
                        }
                    }
                } else {
                    photos = []
                }
            } catch {
                failure = message(for: error)
            }
            isLoading = false
            await recoverSubmissionIfNeeded()
            if pendingCapture == nil, let accountID = try? await repository.currentAccountID() {
                do {
                    if let stored = try captureStore.load(accountID: accountID, appointmentID: appointmentID) {
                        pendingCapture = PendingCapture(metadata: stored.0, original: stored.1, thumbnail: stored.2)
                        isCapturePersisted = true
                    }
                } catch let error as GuinchoInspectionCaptureRecoveryError {
                    switch error {
                    case let .originalUnavailable(metadata), let .integrityMismatch(metadata):
                        unrecoverableCapture = metadata
                        hasUnrecoverableCapture = true
                        failure = "Os arquivos da captura não correspondem à versão registrada. Libere o ponto e tire novamente esta foto."
                    }
                } catch {
                    failure = "Não foi possível recuperar a captura pendente. Tente novamente."
                }
            }
            if pendingCapture != nil { retryPendingCapture() }
        }
    }

    func loadMoreVersions() {
        guard hasMoreVersions, !isLoadingMoreVersions, let cursor = versions.last?.versionNumber else { return }
        isLoadingMoreVersions = true
        Task {
            do {
                let page = try await repository.versions(appointmentID: appointmentID, before: cursor)
                versions.append(contentsOf: page.items)
                hasMoreVersions = page.hasMore
                for version in page.items {
                    let allPhotos = try await listAllPhotos(versionID: version.id)
                    versionPhotos[version.id] = allPhotos
                    for photo in allPhotos where images[photo.id] == nil {
                        let data = try await repository.downloadThumbnail(photo)
                        guard let image = UIImage(data: data) else { throw GuinchoInspectionError.invalidImage }
                        images[photo.id] = image
                    }
                }
            } catch { failure = message(for: error) }
            isLoadingMoreVersions = false
        }
    }

    private func listAllPhotos(versionID: UUID) async throws -> [GuinchoInspectionPhoto] {
        var result: [GuinchoInspectionPhoto] = []
        var afterOrder: Int64?
        var afterID: UUID?
        var hasMore = true
        while hasMore {
            let page = try await repository.photos(
                appointmentID: appointmentID, versionID: versionID, afterOrder: afterOrder, afterID: afterID
            )
            result.append(contentsOf: page.items)
            afterOrder = page.nextOrder
            afterID = page.nextID
            hasMore = page.hasMore
            if hasMore && (afterOrder == nil || afterID == nil) { throw GuinchoInspectionError.contract }
        }
        return result
    }

    func loadMorePhotos() {
        guard hasMorePhotos, !isLoadingMorePhotos, let cursor = photos.last,
              let versionID = document?.summary.currentVersionID else { return }
        isLoadingMorePhotos = true
        Task {
            do {
                let page = try await repository.photos(
                    appointmentID: appointmentID, versionID: versionID, afterOrder: cursor.order, afterID: cursor.id
                )
                photos.append(contentsOf: page.items)
                hasMorePhotos = page.hasMore
                for photo in page.items {
                    let data = try await repository.downloadThumbnail(photo)
                    guard let image = UIImage(data: data) else { throw GuinchoInspectionError.invalidImage }
                    images[photo.id] = image
                }
            } catch {
                failure = message(for: error)
            }
            isLoadingMorePhotos = false
        }
    }

    func loadEnlargedImage(_ photo: GuinchoInspectionPhoto) {
        guard !isLoadingEnlargedImage else { return }
        enlargedImage = nil
        isLoadingEnlargedImage = true
        failure = nil
        Task {
            do {
                    let data = try await repository.download(photo)
                guard let image = UIImage(data: data) else { throw GuinchoInspectionError.invalidImage }
                enlargedImage = image
            } catch { failure = message(for: error) }
            isLoadingEnlargedImage = false
        }
    }

    func capture(_ image: UIImage, point: GuinchoInspectionPoint, detailPoint: String? = nil,
                 caption: String? = nil, replacing: UUID? = nil) {
        guard let document, !isSaving, pendingCapture == nil,
              let versionID = document.summary.currentVersionID else { return }
        guard let original = Self.jpeg(image, maxDimension: 2200, quality: 0.82),
              let thumbnail = Self.jpeg(image, maxDimension: 900, quality: 0.58) else {
            failure = "Não foi possível preparar a foto. Tire outra imagem."
            return
        }
        isSaving = true
        Task {
            var unsavedMetadata: PendingGuinchoInspectionCapture?
            do {
                let accountID = try await repository.currentAccountID()
                let captureID = UUID()
                let metadata = PendingGuinchoInspectionCapture(
                    captureID: captureID, accountID: accountID, appointmentID: appointmentID, versionID: versionID,
                    point: point, detailPoint: detailPoint, caption: caption, replacingPhotoID: replacing, capturedAt: Date(),
                    reserveOperationID: UUID(), confirmOperationID: UUID(),
                    originalFilename: "\(captureID.uuidString).jpg", thumbnailFilename: "\(captureID.uuidString).thumb.jpg",
                    originalSHA256: GuinchoInspectionCaptureStore.sha256(original),
                    originalByteSize: Int64(original.count),
                    thumbnailSHA256: GuinchoInspectionCaptureStore.sha256(thumbnail),
                    thumbnailByteSize: Int64(thumbnail.count)
                )
                unsavedMetadata = metadata
                try captureStore.save(metadata, original: original, thumbnail: thumbnail)
                pendingCapture = PendingCapture(metadata: metadata, original: original, thumbnail: thumbnail)
                isCapturePersisted = true
                isSaving = false
                retryPendingCapture()
            } catch {
                if let metadata = unsavedMetadata {
                    pendingCapture = PendingCapture(metadata: metadata, original: original, thumbnail: thumbnail)
                    isCapturePersisted = false
                }
                failure = "Não foi possível salvar a captura com segurança. Libere espaço e tente novamente."
                isSaving = false
            }
        }
    }

    func retryPendingCapture() {
        guard let document, let pendingCapture, !isSaving else { return }
        isSaving = true
        failure = nil
        Task {
            do {
                if !isCapturePersisted {
                    try captureStore.save(pendingCapture.metadata, original: pendingCapture.original, thumbnail: pendingCapture.thumbnail)
                    isCapturePersisted = true
                }
                self.document = try await repository.capture(
                    jpegData: pendingCapture.original, thumbnailData: pendingCapture.thumbnail,
                    point: pendingCapture.metadata.point, detailPoint: pendingCapture.metadata.detailPoint,
                    caption: pendingCapture.metadata.caption,
                    versionID: pendingCapture.metadata.versionID,
                    replaces: pendingCapture.metadata.replacingPhotoID, capturedAt: pendingCapture.metadata.capturedAt,
                    reserveOperationID: pendingCapture.metadata.reserveOperationID,
                    confirmOperationID: pendingCapture.metadata.confirmOperationID,
                    document: document
                )
                captureStore.remove(pendingCapture.metadata)
                self.pendingCapture = nil
                isCapturePersisted = false
                load()
            } catch {
                failure = message(for: error)
            }
            isSaving = false
        }
    }

    func discardUnrecoverableCapture() {
        guard var metadata = unrecoverableCapture, let document, !document.closed,
              document.summary.state == .draft, !isSaving else { return }
        isSaving = true
        Task {
            do {
                metadata.discardOperationID = metadata.discardOperationID ?? UUID()
                try captureStore.updateManifest(metadata)
                unrecoverableCapture = metadata
                var remoteCaptureWasSaved = (document.requiredPhotos + document.namedPhotos).contains(where: {
                    $0.point == metadata.point
                        && $0.detailPoint == metadata.detailPoint
                        && abs($0.capturedAt.timeIntervalSince(metadata.capturedAt)) < 2
                })
                if let reserved = document.pendingPhotos.first(where: {
                    $0.point == metadata.point
                        && $0.detailPoint == metadata.detailPoint
                }) {
                    self.document = try await repository.discardPendingPhoto(
                        document, photoID: reserved.id, operationID: metadata.discardOperationID ?? UUID()
                    )
                    remoteCaptureWasSaved = false
                }
                captureStore.remove(metadata)
                unrecoverableCapture = nil
                hasUnrecoverableCapture = false
                failure = remoteCaptureWasSaved
                    ? "Esta foto já consta na vistoria do servidor e continua disponível no ponto."
                    : "A foto perdida foi removida. Capture novamente o ponto para continuar."
            } catch {
                if let latest = try? await repository.document(appointmentID: appointmentID) {
                    self.document = latest
                }
                failure = "Não foi possível liberar a captura pendente. Atualize a vistoria e tente novamente."
            }
            isSaving = false
        }
    }

    func submit() {
        guard !isSubmittingIntent, let document, !isSaving,
              document.summary.requiredPointsReady == 4, document.pendingPhotos.isEmpty,
              let versionID = document.summary.currentVersionID else { return }
        isSaving = true
        failure = nil
        isSubmittingIntent = true
        Task {
            defer { isSaving = false; isSubmittingIntent = false }
            do {
                let accountID = try await repository.currentAccountID()
                let intent = loadSubmitIntent()
                    .flatMap { $0.accountID == accountID && $0.appointmentID == appointmentID && $0.versionID == versionID ? $0 : nil }
                    ?? SubmitIntent(accountID: accountID, appointmentID: appointmentID, versionID: versionID, operationID: UUID())
                persistSubmitIntent(intent)
                await performSubmit(intent, document: document)
            } catch {
                failure = message(for: error)
            }
        }
    }

    private func recoverSubmissionIfNeeded() async {
        guard !isSubmittingIntent, let document,
              let intent = loadSubmitIntent(), intent.appointmentID == appointmentID,
              let accountID = try? await repository.currentAccountID(), intent.accountID == accountID else { return }
        isSubmittingIntent = true
        isSaving = true
        defer { isSubmittingIntent = false; isSaving = false }
        await performSubmit(intent, document: document)
    }

    private func performSubmit(_ intent: SubmitIntent, document: GuinchoInspectionDocument) async {
        guard !isSaving || isSubmittingIntent else { return }
        do {
            let result = try await repository.submit(document, operationID: intent.operationID, versionID: intent.versionID)
            self.document = result.inspection
            guard result.outcome == "APPLIED" || result.outcome == "EXISTING" else {
                failure = "A vistoria mudou antes do envio. Atualize a situação e tente novamente."
                load()
                return
            }
            submissionConfirmedID = intent.operationID
            UserDefaults.standard.removeObject(forKey: submitIntentKey)
            load()
        } catch {
            failure = message(for: error)
            load()
        }
    }

    private var submitIntentKey: String { "pitgo.guincho-inspection.submit.\(appointmentID.uuidString)" }
    private func loadSubmitIntent() -> SubmitIntent? {
        guard let data = UserDefaults.standard.data(forKey: submitIntentKey) else { return nil }
        return try? JSONDecoder().decode(SubmitIntent.self, from: data)
    }
    private func persistSubmitIntent(_ intent: SubmitIntent) {
        if let data = try? JSONEncoder().encode(intent) { UserDefaults.standard.set(data, forKey: submitIntentKey) }
    }
    func approve() { mutate { try await self.repository.decide($0, approve: true) } }
    func requestCorrection(reason: String) { mutate { try await self.repository.decide($0, approve: false, reason: reason) } }
    func beginCorrection() { mutate { try await self.repository.beginCorrection($0) } }

    private func mutate(_ operation: @escaping (GuinchoInspectionDocument) async throws -> GuinchoInspectionDocument) {
        guard let current = document, !isSaving else { return }
        isSaving = true
        failure = nil
        Task {
            do { document = try await operation(current); load() }
            catch { failure = message(for: error); load() }
            isSaving = false
        }
    }

    func refreshNow() { load() }
    func consumeSubmissionConfirmation() { submissionConfirmedID = nil }

    private func message(for error: Error) -> String {
        switch error as? GuinchoInspectionError {
        case .closed: "Este atendimento não permite novas alterações na vistoria."
        case .invalidImage: "A foto não está válida. Tire outra imagem."
        case .reasonRequired: "Informe o motivo da correção."
        case .revisionConflict: "O atendimento mudou. Atualize a vistoria antes de continuar."
        case .contract: "Não foi possível confirmar a vistoria. Tente novamente."
        case nil: "Não foi possível concluir agora. Verifique sua conexão e tente novamente."
        }
    }

    private static func jpeg(_ image: UIImage, maxDimension: CGFloat, quality: CGFloat) -> Data? {
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, maxDimension / longest)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.jpegData(withCompressionQuality: quality) { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
