//
//  ProviderRegistrationRepository.swift
//  pitgo
//
//  Consulta o agregado próprio e invoca somente a RPC transacional `create_provider_registration`
//  já existente e compartilhada com o Android (ver contracts/account-provider-database.md de `009`).
//  Nenhum parâmetro de owner/provider é enviado pelo client; nenhum `Error` bruto, mensagem,
//  `details`, header ou payload chega ao ViewModel — somente resultados de domínio sanitizados (ver
//  research.md §10). Catálogo é delegado a `ServiceCatalogRepository` (compartilhado com a Home).
//
//  IMPORTANTE (`009`): `providers.id` (identidade estável da empresa) e `providers.account_id`
//  (owner Auth substituível) nunca devem ser confundidos — o agregado próprio é sempre localizado
//  por `account_id = <conta autenticada>`, nunca por `id`.
//

import Foundation
import Supabase

final class ProviderRegistrationRepository {
    private static let pageSize = 200

    private let client: SupabaseClient
    private let catalogRepository: ServiceCatalogRepository

    init(client: SupabaseClient) {
        self.client = client
        catalogRepository = ServiceCatalogRepository(client: client)
    }

    // MARK: - Catálogo (delegado — compartilhado com a Home)

    func fetchCategories() async -> LoadState<[ServiceCategory]> {
        await catalogRepository.fetchCategories()
    }

    func fetchServices(categoryID: UUID) async -> LoadState<[CatalogService]> {
        await catalogRepository.fetchServices(categoryID: categoryID)
    }

    /// Resolve o serviço único de Móvel (Guincho) ou PitTec para montar a oferta implícita (`016`).
    func fetchImplicitService(dispatchKind: ServiceDispatchKind) async -> ImplicitServiceResolution {
        await catalogRepository.fetchImplicitService(dispatchKind: dispatchKind)
    }

    // MARK: - Agregado próprio

    enum AggregateFetchResult {
        /// Nenhum provider para esta conta — o formulário pode ser aberto.
        case none
        case complete(ProviderSummary)
        /// Provider sem exatamente um endereço ou sem oferta — inconsistência de contrato; o client
        /// não repara isso silenciosamente.
        case inconsistent
        case failure
    }

    func fetchOwnAggregate(accountID: UUID) async -> AggregateFetchResult {
        do {
            let providers: [Provider] = try await client
                .from("providers")
                .select()
                .eq("account_id", value: accountID)
                .limit(1)
                .execute()
                .value
            guard let provider = providers.first else { return .none }

            let addresses: [ProviderAddress] = try await client
                .from("addresses")
                .select()
                .eq("provider_id", value: provider.id)
                .limit(1)
                .execute()
                .value
            guard let address = addresses.first else { return .inconsistent }

            var offerRows: [ProviderServiceRow] = []
            var offset = 0
            while true {
                let page: [ProviderServiceRow] = try await client
                    .from("provider_services")
                    .select()
                    .eq("provider_id", value: provider.id)
                    .order("service_id", ascending: true)
                    .range(from: offset, to: offset + Self.pageSize - 1)
                    .execute()
                    .value
                offerRows += page
                if page.count < Self.pageSize { break }
                offset += Self.pageSize
            }
            guard !offerRows.isEmpty else { return .inconsistent }

            let serviceIDs = Array(Set(offerRows.map(\.serviceID)))
            let services: [CatalogService] = try await client
                .from("services")
                .select()
                .in("id", values: serviceIDs)
                .execute()
                .value
            let categoryIDs = Array(Set(services.map(\.categoryID)))
            let categories: [ServiceCategory] = try await client
                .from("service_categories")
                .select()
                .in("id", values: categoryIDs)
                .execute()
                .value

            let servicesByID = Dictionary(uniqueKeysWithValues: services.map { ($0.id, $0) })
            let categoryNamesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })

            let offers: [ProviderOfferSummary] = offerRows.compactMap { row in
                guard let service = servicesByID[row.serviceID] else { return nil }
                return ProviderOfferSummary(
                    serviceName: service.name,
                    categoryName: categoryNamesByID[service.categoryID] ?? "",
                    price: row.price,
                    durationMinutes: row.durationMinutes,
                    description: row.description
                )
            }
            guard !offers.isEmpty else { return .inconsistent }

            return .complete(ProviderSummary(provider: provider, address: address, offers: offers))
        } catch {
            return .failure
        }
    }

    // MARK: - Submissão atômica (RPC já existente)

    enum SubmissionResult {
        case created(ProviderSummary)
        case alreadyRegistered(ProviderSummary)
        case timeout
        case offline
        case sessionExpired
        case serviceUnavailable
        case emailUnavailable
        case cnpjUnavailable
        case duplicateService
        case catalogChanged
        case geocodeExpired
        case divergenceConfirmationRequired
        case invalidInput
        case contract
        case unknown
    }

    func submit(
        _ command: ProviderRegistrationCommand,
        accountID: UUID,
        geocodeVerificationID: UUID,
        divergenceConfirmed: Bool
    ) async -> SubmissionResult {
        let params = CreateProviderRegistrationParams(
            p_provider: ProviderPayload(
                name: command.company.name,
                description: command.company.description,
                email: command.company.email,
                phone: command.company.phone,
                cnpj: command.company.cnpj,
                location_mode: command.locationMode.rawValue
            ),
            p_offers: command.offers.map {
                OfferPayload(
                    service_id: $0.serviceID,
                    price: Self.canonicalDecimalString($0.price),
                    duration_minutes: $0.durationMinutes,
                    description: $0.description,
                    is_free: $0.isFree
                )
            },
            p_geocode_verification_id: geocodeVerificationID,
            p_divergence_confirmed: divergenceConfirmed
        )

        do {
            let result: CreateProviderRegistrationResult = try await client
                .rpc("create_provider_registration", params: params)
                .execute()
                .value

            switch result.outcome {
            case .created, .alreadyRegistered:
                switch await fetchOwnAggregate(accountID: accountID) {
                case let .complete(summary):
                    return result.outcome == .created ? .created(summary) : .alreadyRegistered(summary)
                default:
                    return .contract
                }
            case .geocodeExpired:
                return .geocodeExpired
            case .divergenceConfirmationRequired:
                return .divergenceConfirmationRequired
            case .catalogChanged:
                return .catalogChanged
            case .emailUnavailable:
                return .emailUnavailable
            case .cnpjUnavailable:
                return .cnpjUnavailable
            case .invalidInput:
                return .invalidInput
            case .sessionBlocked:
                return .sessionExpired
            }
        } catch {
            return classify(error)
        }
    }

    /// Formata sem ponto flutuante binário (`Decimal` → `String` com no máximo duas casas).
    private static func canonicalDecimalString(_ value: Decimal) -> String {
        var rounded = Decimal()
        var input = value
        NSDecimalRound(&rounded, &input, 2, .plain)
        return NSDecimalNumber(decimal: rounded).stringValue
    }

    /// Mapeia somente código Postgres + nomes de constraint allowlisted — usado como rede de
    /// segurança para falhas de transporte/inesperadas que não vieram como `outcome` fechado.
    private func classify(_ error: Error) -> SubmissionResult {
        if let postgrestError = error as? PostgrestError {
            let message = postgrestError.message
            switch postgrestError.code {
            case "23505":
                if message.contains("providers_email") { return .emailUnavailable }
                if message.contains("providers_cnpj") { return .cnpjUnavailable }
                if message.contains("provider_services") { return .duplicateService }
                return .contract
            case "23514", "22023":
                return .contract
            case "42501":
                return .sessionExpired
            default:
                return .unknown
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return .offline
            case .timedOut:
                return .timeout
            default:
                return .serviceUnavailable
            }
        }
        return .unknown
    }
}
