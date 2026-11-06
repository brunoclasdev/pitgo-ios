import AVFoundation
import Combine
import Foundation
import Supabase
import UIKit

@MainActor
final class RegistrationVerificationViewModel: ObservableObject {
    @Published private(set) var registration: RegistrationCase?
    @Published private(set) var busy = false
    @Published private(set) var error: String?
    @Published private(set) var preview: UIImage?
    @Published var cameraPresented = false
    @Published private(set) var cameraDenied = false
    @Published private(set) var selectedKind: RegistrationDocumentKind?
    @Published private(set) var selectedVehicle: UUID?
    @Published private(set) var pendingUpload = false
    private let repository: RegistrationVerificationRepository
    let mode: AccountType
    private var task: Task<Void, Never>?
    private var capture: Data?
    private var reservation: RegistrationEvidenceReservation?
    private var reserveOperation = UUID()
    private var confirmOperation = UUID()
    private var uploaded = false
    private var commandOperation: (signature: String, id: UUID)?

    init(mode: AccountType, repository: RegistrationVerificationRepository) {
        self.mode = mode
        self.repository = repository
    }
    deinit { task?.cancel() }

    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true
        error = nil
        task = Task { [weak self] in
            guard let self else { return }
            defer { busy = false }
            do { try await action() }
            catch is CancellationError { }
            catch { self.error = Self.message(error) }
        }
    }

    func refresh() {
        run { [self] in registration = try await repository.current(mode) }
    }

    func syncComplement() {
        guard !pendingUpload else { return }
        run { [self] in
            try await repository.sync(mode)
            registration = try await repository.current(mode)
        }
    }

    func saveVehicles(_ vehicles: [[String: AnyJSON]]) {
        guard let registration, registration.editable, !pendingUpload else { return }
        var data = registration.data
        data["vehicles"] = .array(vehicles.map(AnyJSON.object))
        perform("save_my_registration_draft", extra: ["p_account_type": .string(mode.rawValue), "p_data": .object(data)])
    }

    func submit() {
        guard let registration, registration.editable, let submission = registration.submission_id, !pendingUpload else { return }
        perform("submit_my_registration", extra: ["p_submission_id": .string(submission.uuidString)])
    }

    func correct() {
        guard let registration, registration.status == .correctionRequested else { return }
        perform("begin_my_registration_correction", extra: ["p_case_id": .string(registration.case_id.uuidString)])
    }

    private func perform(_ name: String, extra: [String: AnyJSON]) {
        guard let registration else { return }
        run { [self] in
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            let encoded = try encoder.encode(extra)
            let signature = name + ":" + String(registration.revision) + ":" + encoded.base64EncodedString()
            let operation: UUID
            if commandOperation?.signature == signature { operation = commandOperation!.id }
            else { operation = UUID(); commandOperation = (signature, operation) }
            self.registration = try await repository.command(name, registration: registration, operation: operation, extra: extra)
            commandOperation = nil
        }
    }

    func requestCamera(kind: RegistrationDocumentKind, vehicle: UUID?) {
        guard registration?.editable == true, !busy, !pendingUpload else { return }
        selectedKind = kind
        selectedVehicle = vehicle
        run { [self] in
            guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                error = "Câmera indisponível neste dispositivo."
                return
            }
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            cameraDenied = !granted
            if granted { cameraPresented = true }
            else { error = "Permita o acesso à câmera nos Ajustes para fotografar seus documentos." }
        }
    }

    func captured(_ image: UIImage) {
        cameraPresented = false
        // Render into a fresh bitmap to remove EXIF/GPS and bound upload size. Never write documents to disk.
        let scale = min(1, 2000 / max(image.size.width, image.size.height))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let normalized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let bytes = normalized.jpegData(compressionQuality: 0.85), bytes.count <= 10 * 1024 * 1024 else {
            error = "Não foi possível preparar a foto. Fotografe novamente."
            return
        }
        capture = bytes
        preview = normalized
        reservation = nil
        uploaded = false
        reserveOperation = UUID()
        confirmOperation = UUID()
    }

    func confirmPhoto() {
        guard capture != nil, selectedKind != nil else { return }
        preview = nil
        pendingUpload = true
        retryUpload()
    }

    func discardPendingUpload() {
        guard !busy else { return }
        capture = nil
        reservation = nil
        pendingUpload = false
        uploaded = false
        refresh()
    }

    func retryUpload() {
        guard let bytes = capture, let kind = selectedKind, let registration, registration.submission_id != nil else { return }
        run { [self] in
            if reservation == nil {
                reservation = try await repository.reserve(registration, kind: kind, vehicle: selectedVehicle, size: bytes.count, operation: reserveOperation)
            }
            guard let reservation else { return }
            if !uploaded {
                try await repository.upload(reservation, bytes: bytes)
                uploaded = true
            }
            try await repository.confirm(reservation, operation: confirmOperation)
            self.registration = try await repository.current(mode)
            capture = nil
            self.reservation = nil
            pendingUpload = false
        }
    }

    func showPhoto(_ evidence: RegistrationEvidence) {
        run { [self] in
            let bytes = try await repository.photo(evidence.storage_path)
            preview = UIImage(data: bytes)
        }
    }
    var isCapturePreview: Bool { capture != nil && !pendingUpload }
    func closePreview() {
        preview = nil
        if !pendingUpload { capture = nil }
    }

    static func message(_ error: Error) -> String {
        if let error = error as? URLError {
            return error.code == .timedOut ? "A operação demorou demais. Tente novamente." : "Verifique sua conexão e tente novamente."
        }
        if let error = error as? PostgrestError {
            switch error.code {
            case "40001": return "O cadastro foi atualizado. Toque em Atualizar situação antes de continuar."
            case "42501": return "Não foi possível autorizar esta operação. Atualize a situação ou entre novamente."
            case "22023": return "Confira os dados e as fotos obrigatórias antes de continuar."
            default: break
            }
        }
        return "Não foi possível concluir agora. Atualize a situação e tente novamente."
    }
}
