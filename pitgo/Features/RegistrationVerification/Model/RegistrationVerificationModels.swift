import Foundation
import Supabase

enum RegistrationReviewStatus: String, Decodable {
    case incomplete = "INCOMPLETE"
    case inReview = "IN_REVIEW"
    case correctionRequested = "CORRECTION_REQUESTED"
    case approved = "APPROVED"

    var title: String {
        switch self {
        case .incomplete: "Complete seu cadastro"
        case .inReview: "Cadastro em análise"
        case .correctionRequested: "Correção solicitada"
        case .approved: "Cadastro aprovado"
        }
    }
}

struct RegistrationMembership: Decodable {
    let account_type: AccountType
    let verification_status: RegistrationReviewStatus?
    let can_use_marketplace: Bool
    let legacy_exempt: Bool
}

struct RegistrationCase: Decodable {
    let case_id: UUID
    let account_type: AccountType
    let status: RegistrationReviewStatus?
    let revision: Int
    let submission_id: UUID?
    let submission_state: String?
    let data: [String: AnyJSON]
    let pending_items: [String]
    let evidence: [RegistrationEvidence]
    let reviews: [RegistrationReview]

    var editable: Bool { submission_state == "DRAFT" && (status == .incomplete || status == .correctionRequested) }
    var vehicles: [[String: AnyJSON]] { data["vehicles"]?.arrayValue?.compactMap(\.objectValue) ?? [] }
}

struct RegistrationEvidence: Decodable, Identifiable {
    let id: UUID
    let kind: RegistrationDocumentKind
    let vehicle_reference_id: UUID?
    let storage_path: String
    let upload_state: String
}

struct RegistrationReview: Decodable {
    let result: String
    let reason: String?
    let correction_items: [String]
}

enum RegistrationDocumentKind: String, Decodable, CaseIterable {
    case cnhFront = "CNH_FRONT"
    case cnhBack = "CNH_BACK"
    case selfie = "SELFIE"
    case selfieWithDocument = "SELFIE_WITH_DOCUMENT"
    case vehicleDocument = "VEHICLE_DOCUMENT"

    var title: String {
        switch self {
        case .cnhFront: "CNH — frente"
        case .cnhBack: "CNH — verso"
        case .selfie: "Selfie"
        case .selfieWithDocument: "Selfie segurando a CNH"
        case .vehicleDocument: "Documento do veículo"
        }
    }
    var guidance: String {
        switch self {
        case .selfie: "Enquadre seu rosto inteiro, com boa iluminação e sem acessórios que o cubram."
        case .selfieWithDocument: "Segure a CNH ao lado do rosto. Mantenha o rosto e o documento visíveis e legíveis."
        default: "Enquadre o documento inteiro, sem cortes ou reflexos. Confira se os dados estão legíveis antes de enviar."
        }
    }
}

struct RegistrationEvidenceReservation: Decodable {
    let evidence_id: UUID
    let object_path: String
    let revision: Int
}
