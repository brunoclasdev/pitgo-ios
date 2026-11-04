//
//  ProviderRegistrationModels.swift
//  pitgo
//
//  Estados e tipos do fluxo de cadastro de empresa prestadora (ver data-model.md de `007`/`009`). O
//  rascunho e o comando vivem somente em memória do ViewModel — nunca `Codable`/persistido e nunca
//  contêm owner/provider/categoria ID (FR-016). Endereço não tem mais latitude/longitude manuais —
//  a coordenada vem exclusivamente da verificação (`geocode-provider-address` + fix do dispositivo,
//  ver `ProviderAddressVerificationState`).
//

import Foundation

// MARK: - Rascunho editável

struct CompanyDraft {
    var name: String = ""
    var description: String = ""
    var email: String
    var phone: String = ""
    var cnpj: String = ""
}

struct AddressDraft: Equatable {
    var street: String = ""
    var number: String = ""
    var neighborhood: String = ""
    var postalCode: String = ""
    var city: String = ""
    var state: BrazilianState?
    var complement: String = ""
    // País não é editável; sempre "BR". Sem latitude/longitude manuais — ver
    // `ProviderAddressVerificationState`.
}

/// `id` é um localID estável apenas para UI/erro/foco — nunca reindexado, mesmo após remoção de
/// outra oferta. `026`: a categoria deixou de pertencer à oferta — agora é única por rascunho
/// (`ProviderRegistrationDraft.primaryCategoryID`), compartilhada por todas as ofertas Fixo.
struct OfferDraft: Identifiable {
    let id = UUID()
    var serviceID: UUID?
    var isFree: Bool = false
    var priceInput: String = ""
    var durationInput: String = ""
    var description: String = ""
}

struct ProviderRegistrationDraft {
    var company: CompanyDraft
    var address = AddressDraft()
    var providerKind: ProviderKind = .guincho
    var vehiclePlate = ""
    var vehicleMake = ""
    var vehicleModel = ""
    var vehicleColor = ""
    var guinchoSizeID: UUID?
    var locationMode: ProviderLocationMode = .fixed
    /// `026` FR-001: categoria principal única do prestador Fixo; todas as ofertas pertencem a ela.
    /// `nil` para Móvel/PitTec (não escolhem categoria).
    var primaryCategoryID: UUID?
    var offers: [OfferDraft] = [OfferDraft()]

    /// `true` quando algum campo não sensível já foi preenchido — usado para exigir confirmação de
    /// descarte ao voltar.
    var hasMeaningfulContent: Bool {
        !company.name.trimmingCharacters(in: .whitespaces).isEmpty
            || !company.cnpj.isEmpty
            || !address.street.trimmingCharacters(in: .whitespaces).isEmpty
            || primaryCategoryID != nil
            || offers.contains { $0.serviceID != nil || !$0.priceInput.isEmpty }
    }

    /// `026`: ofertas com algum dado preenchido — usado para exigir confirmação antes de trocar a
    /// categoria principal e descartar a seleção atual.
    var offersHaveMeaningfulContent: Bool {
        offers.contains {
            $0.serviceID != nil
                || !$0.priceInput.trimmingCharacters(in: .whitespaces).isEmpty
                || !$0.durationInput.trimmingCharacters(in: .whitespaces).isEmpty
                || !$0.description.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }
}

// MARK: - Verificação de endereço (geocoding + comparação com o dispositivo — ver research.md §5/§6)

enum GeocodingFailureReason: Hashable {
    case noMatch
    case ambiguousOrPartial
    case wrongRegion
    case fixTooOld
    case fixTooImprecise
    case invalidAddress
    case rateLimited
    case upstreamUnavailable
    case sessionBlocked
    case permissionDenied
    case serviceDisabled
    case timeout
    case offline
    case unknown
}

/// Editar qualquer campo do endereço retorna a `.unverified`. Somente `.matched`/
/// `.confirmedDivergence` com `expiresAt` no futuro habilitam o submit.
///
/// Achado desta sessão (device físico real, iOS não completava nenhum cadastro): o Edge Function
/// `geocode-provider-address` real (conferido no fonte do repo Android, mesmo backend) não usa mais
/// fix de GPS do dispositivo — geocodifica só o texto do endereço via MapTiler e devolve um
/// `verification_token` (string opaca), não mais um `verification_id` (UUID) como o design original
/// de `009` previa. `device_distance_m`/`mismatch_confirmed` vêm hardcoded (0/true) no servidor
/// atual, então `.diverged`/`.confirmedDivergence` na prática nunca mais acontecem — mantidos aqui
/// só por paridade estrutural com o Android (que faz a mesma escolha), não removidos para não
/// arrancar o diálogo de confirmação de divergência (`ProviderRegistrationView`) sem necessidade.
enum ProviderAddressVerificationState: Equatable {
    case unverified
    case geocoding
    case matched(token: String, expiresAt: Date)
    case diverged(token: String, distanceMeters: Double, expiresAt: Date)
    case confirmedDivergence(token: String, distanceMeters: Double, expiresAt: Date)
    case failure(reason: GeocodingFailureReason)

    var isUsableForSubmit: Bool {
        switch self {
        case let .matched(_, expiresAt), let .confirmedDivergence(_, _, expiresAt):
            expiresAt > Date()
        default:
            false
        }
    }

    var verificationToken: String? {
        switch self {
        case let .matched(token, _), let .diverged(token, _, _), let .confirmedDivergence(token, _, _):
            token
        default:
            nil
        }
    }

    var isDivergenceConfirmed: Bool {
        if case .confirmedDivergence = self { return true }
        return false
    }
}

// MARK: - Campos e erros

enum ProviderCompanyField: Hashable, CaseIterable {
    case name, description, email, phone, cnpj
}

enum ProviderAddressField: Hashable, CaseIterable {
    case postalCode, street, number, complement, neighborhood, city, state
}

enum OfferField: Hashable, CaseIterable {
    case service, price, duration, description
}

enum ProviderVehicleField: Hashable { case plate, make, model, color, size }

/// Identificado por `localID` (nunca por índice) para que remoção/reordenação não mova erro/foco
/// para outra oferta.
enum ProviderField: Hashable {
    case company(ProviderCompanyField)
    case address(ProviderAddressField)
    case locationMode
    case vehicle(ProviderVehicleField)
    /// `026`: categoria única do rascunho Fixo — substitui o antigo `.offer(_, field: .category)`.
    case primaryCategory
    case offersList
    case offer(localID: UUID, field: OfferField)
}

enum ProviderFieldError: Hashable {
    case required
    case invalidFormat
    case outOfRange
    case unavailable
    case duplicate
    case notFound
}

struct ProviderFocusRequest: Equatable {
    let field: ProviderField
    let requestID: Int
}

// MARK: - Comando normalizado (nunca contém ID de owner/provider/categoria)

struct NormalizedCompany {
    let name: String
    let description: String?
    let email: String
    let phone: String
    let cnpj: String
}

/// Usado tanto para o payload de `geocode-provider-address` quanto para `p_address` da RPC de
/// cadastro (que grava o texto do endereço direto, junto do `verification_token` da prova — ver
/// nota em `ProviderAddressVerificationState`).
struct NormalizedAddress {
    let street: String
    let number: String
    let neighborhood: String
    let zipCode: String
    let city: String
    let state: String
    let country: String
    let complement: String?
}

struct NormalizedOffer {
    let serviceID: UUID
    let price: Decimal
    let durationMinutes: Int
    let description: String?
    let isFree: Bool
}

struct ProviderRegistrationCommand {
    let company: NormalizedCompany
    let address: NormalizedAddress
    let providerKind: ProviderKind
    let vehicle: NormalizedProviderVehicle?
    let locationMode: ProviderLocationMode
    let offers: [NormalizedOffer]
}

struct NormalizedProviderVehicle {
    let plate: String
    let make: String
    let model: String
    let color: String
    var guinchoSizeID: UUID? = nil
}

// MARK: - Resumo (apresentação — nenhum ID interno; CNPJ mascarado pela View)

struct ProviderOfferSummary {
    let serviceName: String
    let categoryName: String
    let price: Decimal
    let durationMinutes: Int
    let description: String?

    var isFree: Bool { price == 0 }
}

struct ProviderSummary {
    let provider: Provider
    let address: ProviderAddress
    let offers: [ProviderOfferSummary]
}

// MARK: - Carregamento de catálogo

enum LoadState<Value> {
    case loading
    case empty
    case content(Value)
    case failure(reason: String)
}

// MARK: - Busca de endereço por CEP (011 — ViaCEP; ver data-model.md)

/// Resultado canônico aceito do ViaCEP. Campos administrativos (unidade, região, IBGE, GIA, DDD,
/// SIAFI) não pertencem a este modelo (FR-015).
struct PostalAddressResult: Equatable {
    let postalCode: String
    let street: String?
    let complement: String?
    let neighborhood: String?
    let city: String
    let state: BrazilianState
}

enum PostalCodeLookupFailure: Hashable {
    case offline
    case timeout
    case serviceUnavailable
    case unexpectedResponse
}

enum PostalCodeLookupResult {
    case found(PostalAddressResult)
    case notFound
    case failure(PostalCodeLookupFailure)
}

enum CepAddressField: Hashable, CaseIterable {
    case street, complement, neighborhood, city, state
}

/// Relaciona o CEP resolvido ao conjunto de campos preenchidos pela resposta — usado para invalidar
/// somente esses campos quando a pessoa altera o CEP novamente (data-model.md "Transições").
struct CepAutofillProvenance: Equatable {
    let postalCode: String
    let fields: Set<CepAddressField>
}

/// `attemptID` é monotônico durante a vida do ViewModel; apenas uma tentativa pode estar `.loading`
/// por vez; um estado só é aplicável ao CEP nele armazenado.
enum PostalCodeLookupState: Equatable {
    case idle
    case loading(attemptID: UInt64, postalCode: String)
    case found(attemptID: UInt64, postalCode: String, appliedFields: Set<CepAddressField>)
    case notFound(attemptID: UInt64, postalCode: String)
    case failure(attemptID: UInt64, postalCode: String, reason: PostalCodeLookupFailure)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

// MARK: - Estado raiz

enum ProviderStartupFailureReason: Hashable {
    case offline
    case service
    case unknown
}

enum ProviderFailureReason: Hashable {
    case timeout
    case offline
    case sessionExpired
    case serviceUnavailable
    case duplicateService
    case catalogChanged
    case geocodeExpired
    case divergenceConfirmationRequired
    case invalidInput
    case contract
    case unknown
}

enum EditingSubmission: Equatable {
    case idle
    case submitting
    case failure(reason: ProviderFailureReason)
}

/// `026`: troca de categoria principal pendente de confirmação — a troca só é aplicada (e as ofertas
/// descartadas) depois que o prestador confirma, nunca de forma silenciosa (contracts/
/// provider-service-selection.md "Troca de categoria e compatibilidade").
struct PendingPrimaryCategoryChange: Equatable {
    let newCategoryID: UUID?
}

struct EditingContent {
    var draft: ProviderRegistrationDraft
    var categories: LoadState<[ServiceCategory]> = .loading
    var servicesByCategory: [UUID: LoadState<[CatalogService]>] = [:]
    var addressVerification: ProviderAddressVerificationState = .unverified
    var fieldErrors: [ProviderField: ProviderFieldError] = [:]
    var focusRequest: ProviderFocusRequest?
    var submission: EditingSubmission = .idle
    var postalCodeLookup: PostalCodeLookupState = .idle
    var cepAutofillProvenance: CepAutofillProvenance?
    var pendingPrimaryCategoryChange: PendingPrimaryCategoryChange?
    /// `nil` para modalidade Fixo (nenhuma resolução acontece); para Móvel/PitTec, reflete a busca
    /// do serviço único daquele `dispatchKind` (`016`) — `.loading` desabilita o envio.
    var implicitService: LoadState<CatalogService>?

    var isSubmitting: Bool {
        if case .submitting = submission { return true }
        return false
    }

    var isVerifyingLocation: Bool {
        addressVerification == .geocoding
    }

    var isInputEnabled: Bool { !isSubmitting && !isVerifyingLocation }

    /// Somente os cinco campos deriváveis do CEP ficam desabilitados durante a consulta — CEP,
    /// Número e o restante do formulário permanecem utilizáveis (data-model.md "Transições").
    var isAddressLookupLoading: Bool { postalCodeLookup.isLoading }

    /// Móvel/PitTec (`016`) não exibem categoria/serviço/preço/duração — o serviço único da
    /// modalidade é resolvido e anexado automaticamente.
    var showsOffersSection: Bool { draft.locationMode == .fixed && draft.providerKind != .store }

    /// Móvel só pede preço/duração (serviço já resolvido); PitTec não pede nada (preço/duração
    /// internos, sem significado de cobrança).
    var showsMobilePriceFields: Bool { draft.providerKind == .guincho }

    /// A partir desta sessão, não exige mais `addressVerification.isUsableForSubmit` — no Android
    /// (mesmo backend, `ProviderRegistrationViewModel.proceedWithValidation`/`geocodeAndSubmit`) o
    /// botão nunca ficou preso a essa verificação: ela roda automaticamente no envio quando ainda
    /// não foi feita (ou expirou), em vez de travar o botão até um toque manual em "Verificar
    /// endereço". Ver `ProviderRegistrationViewModel.submit()`/`verifyAddressThenSubmit(command:)`.
    var canSubmit: Bool {
        guard !isSubmitting else { return false }
        if draft.locationMode == .fixed { return true }
        if case .content = implicitService { return true }
        return false
    }
}

enum ProviderRegistrationUiState {
    case loading
    case startupFailure(reason: ProviderStartupFailureReason)
    case editing(EditingContent)
    case alreadyRegistered(ProviderSummary)
    case success(ProviderSummary)
    case sessionExpired
}
