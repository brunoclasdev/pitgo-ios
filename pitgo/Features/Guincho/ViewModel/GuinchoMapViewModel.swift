//
//  GuinchoMapViewModel.swift
//  pitgo
//
//  `028` (porte do app Android — `GuinchoMapViewModel.kt`): estágios retirada → destino → confirmar
//  → descoberta, antes de qualquer pagamento. "Contratar" (`contract()`) cria a solicitação
//  (`GuinchoRepository.reserve`) e devolve o snapshot de despacho compartilhado (`013`) para quem
//  apresenta esta tela assumir o acompanhamento — este ViewModel nunca observa o pós-aceite.
//

import Combine
import CoreLocation
import Foundation

enum GuinchoMapStage {
    case pickup, destination, confirm, discovery
}

enum GuinchoMapOperation {
    case idle, locating, resolvingAddress, saving, discovering, quoting, reserving
}

struct GuinchoMapState {
    var stage: GuinchoMapStage = .pickup
    var operation: GuinchoMapOperation = .idle
    var vehicles: [Vehicle] = []
    var vehicleID: UUID?
    var pickupAddress: String = ""
    var destinationAddress: String = ""
    var destinationNumber: String = ""
    var pickup: CLLocationCoordinate2D?
    var destination: CLLocationCoordinate2D?
    var addressSuggestions: [GuinchoAddressSuggestion] = []
    var searchingAddress: Bool = false
    var addressSearchFailure: Bool = false
    var addressSearchCompleted: Bool = false
    var destinationNumberNotFound: Bool = false
    /// Centro do mapa — a retirada em `.pickup` é sempre `viewport` (crosshair), nunca um marcador.
    var viewport: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: -14.235, longitude: -51.9253)
    var providers: [GuinchoProvider] = []
    var selected: GuinchoProvider?
    var quote: GuinchoQuote?
    var draft: GuinchoDraft?
    var failure: GuinchoFailureReason?
    var locationUnavailable: Bool = false
    /// Snapshot devolvido por `contract()` assim que a solicitação é criada — sinal para a View
    /// navegar para o acompanhamento (`013`), nunca renderizado por esta própria tela.
    var checkout: MobileDispatchSnapshot?
    /// Incrementado a cada novo enquadramento desejado (abertura da descoberta, seleção de
    /// prestador) — consumido por `PitGoMapView.fitTrigger` (mesma técnica de `026`).
    var fitTrigger: Int = 0
    var fitCoordinates: [CLLocationCoordinate2D]?

    var fullDestinationAddress: String {
        let parts = destinationAddress.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        let street = parts.first ?? destinationAddress.trimmingCharacters(in: .whitespaces)
        let rest = parts.count > 1 ? parts[1] : ""
        return [street, destinationNumber.trimmingCharacters(in: .whitespaces), rest]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    var canConfirmDestination: Bool {
        destination != nil && !searchingAddress && !destinationAddress.trimmingCharacters(in: .whitespaces).isEmpty
            && !destinationNumber.trimmingCharacters(in: .whitespaces).isEmpty && fullDestinationAddress.count <= 500
    }
}

@MainActor
final class GuinchoMapViewModel: ObservableObject {
    @Published private(set) var state = GuinchoMapState()

    private let userID: UUID
    private let repository: GuinchoRepository
    private let vehicleRepository: VehicleRepository
    private let locationRepository: DeviceLocationRepository
    private let addressRepository: GuinchoAddressRepository

    private var work: Task<Void, Never>?
    private var discoveryTask: Task<Void, Never>?
    private var addressTask: Task<Void, Never>?
    private var addressRevision = 0
    private var destinationFromMapGesture = false
    private var selectedDestinationSuggestion: GuinchoAddressSuggestion?
    /// Preserva a mesma operação (`operation_id`) de `contract()` entre retoques enquanto a mesma
    /// cotação segue válida — reenviar o mesmo toque nunca duplica a solicitação.
    private var contractQuoteID: UUID?
    private var contractOperationID: UUID?

    init(
        userID: UUID,
        repository: GuinchoRepository,
        vehicleRepository: VehicleRepository,
        locationRepository: DeviceLocationRepository,
        addressRepository: GuinchoAddressRepository
    ) {
        self.userID = userID
        self.repository = repository
        self.vehicleRepository = vehicleRepository
        self.locationRepository = locationRepository
        self.addressRepository = addressRepository
    }

    func start() {
        loadVehicles()
    }

    func loadVehicles() {
        Task { [weak self] in
            guard let self else { return }
            guard let vehicles = await vehicleRepository.listActiveVehicles(userID: userID) else {
                update { $0.failure = .serviceUnavailable }
                return
            }
            update {
                $0.vehicles = vehicles
                if $0.vehicleID == nil { $0.vehicleID = vehicles.first?.id }
                $0.failure = nil
            }
        }
    }

    // MARK: - Localização / retirada

    func locationDenied() {
        update { $0.locationUnavailable = true }
    }

    /// Mesmo padrão de permissão já usado em `ClientMobileDispatchViewModel.beginNewSearch` —
    /// `.notDetermined` dispara o prompt do sistema e segue para `requestOneShotFix`, que resolve a
    /// autorização internamente; `.denied`/`.restricted` nunca chegam a pedir um fix.
    func locate() {
        guard state.operation == .idle else { return }
        let selectingPickup = state.stage == .pickup
        let selectingDestination = state.stage == .destination
        guard selectingPickup || selectingDestination else { return }
        switch locationRepository.authorizationStatus {
        case .denied, .restricted:
            update { $0.locationUnavailable = true }
            return
        case .notDetermined:
            locationRepository.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            break
        }
        guard DeviceLocationServiceStatus.isEnabled else {
            update { $0.locationUnavailable = true }
            return
        }
        update { $0.operation = .locating }
        Task { [weak self] in
            guard let self else { return }
            switch await locationRepository.requestOneShotFix(timeout: 10) {
            case let .success(fix):
                let coordinate = CLLocationCoordinate2D(latitude: fix.latitude, longitude: fix.longitude)
                update { $0.viewport = coordinate; $0.locationUnavailable = false; $0.operation = .idle }
                if selectingPickup {
                    await applyPickup(coordinate)
                } else if selectingDestination, state.stage == .destination {
                    destinationFromMapGesture = false
                    await resolveDestinationPoint(coordinate)
                }
            default:
                update { $0.locationUnavailable = true; $0.operation = .idle }
            }
        }
    }

    private func applyPickup(_ coordinate: CLLocationCoordinate2D) async {
        let address = await addressRepository.pickupAddress(coordinate)
        update {
            $0.pickup = coordinate
            $0.pickupAddress = address
            $0.stage = .destination
            $0.operation = .idle
            $0.failure = nil
            $0.locationUnavailable = false
        }
    }

    // MARK: - Mapa (gesto do usuário)

    /// `PitGoMapView.onRegionChanged` já só dispara ao final de um gesto (pan/zoom) — cobre, num só
    /// callback, o que o Android separa em `viewport()` (contínuo) + `mapGesture()` (discreto).
    func userRepositionedMap(to coordinate: CLLocationCoordinate2D) {
        update { $0.viewport = coordinate }
        guard state.stage == .destination else { return }
        destinationFromMapGesture = true
        selectedDestinationSuggestion = nil
        cancelAddressSearch()
        update {
            $0.destination = nil
            $0.addressSuggestions = []
            $0.searchingAddress = false
            $0.addressSearchFailure = false
            $0.addressSearchCompleted = false
            $0.destinationNumberNotFound = false
        }
        Task { [weak self] in
            await self?.resolveDestinationPoint(coordinate)
        }
    }

    private func cancelAddressSearch() {
        addressRevision += 1
        addressTask?.cancel()
        addressTask = nil
        if state.operation == .resolvingAddress { update { $0.operation = .idle } }
    }

    private func resolveDestinationPoint(_ coordinate: CLLocationCoordinate2D) async {
        guard CLLocationCoordinate2DIsValid(coordinate) else { return }
        cancelAddressSearch()
        selectedDestinationSuggestion = nil
        let revision = addressRevision
        update {
            $0.destination = nil
            $0.destinationAddress = ""
            $0.searchingAddress = true
            $0.addressSuggestions = []
            $0.addressSearchFailure = false
            $0.addressSearchCompleted = false
            $0.destinationNumberNotFound = false
        }
        let label = await addressRepository.destinationAddress(coordinate)
        guard revision == addressRevision, state.stage == .destination else { return }
        update { $0.destination = coordinate; $0.destinationAddress = label; $0.searchingAddress = false }
    }

    // MARK: - Campo de endereço (destino)

    func updateDestinationAddress(_ value: String) {
        guard state.stage == .destination else { return }
        let query = String(value.prefix(200))
        // O `TextField` reemite o `set` do binding ao perder foco logo após uma seleção (o UIKit
        // comita o texto ao resignar first responder) — sem este guard, esse eco desfaz o que
        // `chooseDestination`/`userRepositionedMap` acabou de aplicar e reinicia a busca sozinho,
        // reexibindo a sugestão recém-escolhida depois de um novo "carregando" (achado real desta
        // sessão).
        guard query != state.destinationAddress else { return }
        cancelAddressSearch()
        destinationFromMapGesture = false
        selectedDestinationSuggestion = nil
        let revision = addressRevision
        let willSearch = query.trimmingCharacters(in: .whitespaces).count >= 3
        update {
            $0.destinationAddress = query
            $0.destination = nil
            $0.addressSuggestions = []
            $0.searchingAddress = willSearch
            $0.addressSearchCompleted = false
            $0.addressSearchFailure = false
            $0.destinationNumberNotFound = false
            $0.failure = nil
        }
        guard willSearch else { return }
        addressTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            let proximity = state.pickup ?? state.viewport
            let result = await addressRepository.suggestions(query: query.trimmingCharacters(in: .whitespaces), proximity: proximity)
            guard revision == addressRevision, state.stage == .destination else { return }
            switch result {
            case let .success(suggestions):
                update { $0.addressSuggestions = suggestions; $0.searchingAddress = false; $0.addressSearchCompleted = true }
            case let .failure(reason):
                update {
                    $0.searchingAddress = false
                    $0.addressSearchFailure = true
                    if reason == .sessionExpired { $0.failure = reason }
                }
            }
        }
    }

    func chooseDestination(_ suggestion: GuinchoAddressSuggestion) {
        guard state.stage == .destination, state.addressSuggestions.contains(suggestion) else { return }
        cancelAddressSearch()
        destinationFromMapGesture = false
        selectedDestinationSuggestion = suggestion
        update {
            $0.destination = suggestion.coordinate
            $0.destinationAddress = suggestion.label
            $0.addressSuggestions = []
            $0.searchingAddress = false
            $0.addressSearchCompleted = false
            $0.addressSearchFailure = false
            $0.destinationNumberNotFound = false
            $0.failure = nil
        }
    }

    func updateDestinationNumber(_ value: String) {
        guard state.stage == .destination else { return }
        if state.operation == .resolvingAddress { cancelAddressSearch() }
        update {
            $0.destinationNumber = String(value.filter { !$0.isNewline }.prefix(20))
            $0.destinationNumberNotFound = false
            $0.addressSearchFailure = false
            $0.failure = nil
        }
    }

    func selectVehicle(_ id: UUID) {
        guard state.stage != .discovery else { return }
        update { $0.vehicleID = id }
    }

    // MARK: - Confirmação de ponto

    func confirmPoint() {
        guard state.operation == .idle, state.stage == .pickup || state.stage == .destination else { return }
        if state.stage == .pickup {
            guard CLLocationCoordinate2DIsValid(state.viewport) else {
                update { $0.failure = .invalidInput }
                return
            }
            update { $0.operation = .locating }
            let coordinate = state.viewport
            Task { [weak self] in
                await self?.applyPickup(coordinate)
            }
            return
        }

        guard state.canConfirmDestination, let destination = state.destination, CLLocationCoordinate2DIsValid(destination), !destinationFromMapGesture else {
            update { $0.failure = .invalidInput }
            return
        }

        guard let suggestion = selectedDestinationSuggestion, state.destinationNumber.trimmingCharacters(in: .whitespaces).lowercased() != "s/n" else {
            confirmDestination(destination)
            return
        }

        let revision = addressRevision
        update { $0.operation = .resolvingAddress; $0.destinationNumberNotFound = false; $0.addressSearchFailure = false; $0.failure = nil }
        let fullAddress = state.fullDestinationAddress
        let number = state.destinationNumber.trimmingCharacters(in: .whitespaces)
        addressTask = Task { [weak self] in
            guard let self else { return }
            let result = await addressRepository.resolveDestination(address: fullAddress, number: number, proximity: suggestion.coordinate)
            guard revision == addressRevision, state.stage == .destination else { return }
            switch result {
            case let .success(suggestions):
                if let resolved = suggestions.first {
                    confirmDestination(resolved.coordinate)
                } else {
                    update { $0.operation = .idle; $0.destinationNumberNotFound = true }
                }
            case let .failure(reason):
                update { $0.operation = .idle; $0.addressSearchFailure = true; if reason == .sessionExpired { $0.failure = reason } }
            }
        }
    }

    private func confirmDestination(_ coordinate: CLLocationCoordinate2D) {
        guard let pickup = state.pickup else { return }
        update {
            $0.stage = .confirm
            $0.operation = .idle
            $0.destination = coordinate
            $0.addressSuggestions = []
            $0.destinationNumberNotFound = false
            $0.fitCoordinates = [pickup, coordinate]
            $0.fitTrigger += 1
        }
    }

    func editTrip() {
        guard state.operation != .reserving else { return }
        work?.cancel()
        discoveryTask?.cancel()
        cancelAddressSearch()
        destinationFromMapGesture = false
        update {
            $0.stage = .destination
            $0.operation = .idle
            $0.providers = []
            $0.selected = nil
            $0.quote = nil
            $0.failure = nil
            $0.searchingAddress = false
            $0.addressSuggestions = []
            $0.addressSearchCompleted = false
            $0.addressSearchFailure = false
            $0.destinationNumberNotFound = false
        }
    }

    // MARK: - Descoberta

    func confirmTrip() {
        guard let pickup = state.pickup, let destination = state.destination,
              !state.destinationNumber.trimmingCharacters(in: .whitespaces).isEmpty,
              let vehicleID = state.vehicleID else {
            update { $0.failure = .invalidInput }
            return
        }
        let input = GuinchoTripInput(
            vehicleID: vehicleID,
            pickupAddress: state.pickupAddress,
            pickup: pickup,
            destinationAddress: state.fullDestinationAddress,
            destination: destination
        )
        guard input.isValid else {
            update { $0.failure = .invalidInput }
            return
        }
        work?.cancel()
        let previousDraft = state.draft
        update { $0.operation = .saving; $0.failure = nil }
        work = Task { [weak self] in
            guard let self else { return }
            switch await repository.saveTrip(input, previous: previousDraft) {
            case let .failure(reason):
                failed(reason)
            case let .success(draft):
                update {
                    $0.draft = draft
                    $0.stage = .discovery
                    $0.fitCoordinates = [pickup]
                    $0.fitTrigger += 1
                }
                await discover(draft)
            }
        }
    }

    func refresh() {
        guard state.operation != .reserving, let draft = state.draft else { return }
        work?.cancel()
        work = Task { [weak self] in await self?.discover(draft) }
    }

    private func discover(_ draft: GuinchoDraft) async {
        update { $0.operation = .discovering; $0.selected = nil; $0.quote = nil; $0.failure = nil }
        switch await repository.discover(draft: draft) {
        case let .success(providers):
            update { $0.providers = providers; $0.operation = .idle }
        case let .failure(reason):
            failed(reason)
        }
    }

    /// Mesmo intervalo de 5s do Android — só reconsulta quando em descoberta, ocioso e sem checkout
    /// já criado.
    func startDiscoveryUpdates() {
        guard discoveryTask == nil else { return }
        discoveryTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { return }
                guard let draft = state.draft, state.stage == .discovery, state.operation == .idle, state.checkout == nil else { continue }
                switch await repository.discover(draft: draft) {
                case let .success(providers):
                    guard state.draft == draft, state.stage == .discovery, state.operation == .idle, state.checkout == nil else { continue }
                    let selected = providers.first { $0.id == state.selected?.id }
                    update { $0.providers = providers; $0.selected = selected; if selected == nil { $0.quote = nil } }
                case let .failure(reason) where reason == .sessionExpired:
                    update { $0.failure = reason }
                case .failure:
                    break
                }
            }
        }
    }

    func stopDiscoveryUpdates() {
        discoveryTask?.cancel()
        discoveryTask = nil
    }

    func selectProvider(id: UUID) {
        guard state.operation != .reserving, state.stage == .discovery else { return }
        guard let provider = state.providers.first(where: { $0.id == id }), let draft = state.draft else { return }
        work?.cancel()
        update { $0.selected = provider; $0.quote = nil; $0.operation = .quoting; $0.failure = nil }
        work = Task { [weak self] in
            guard let self else { return }
            switch await repository.quote(draft: draft, providerID: provider.id) {
            case let .success(quote):
                guard state.selected?.id == provider.id, state.draft == draft else { return }
                update { $0.quote = quote; $0.operation = .idle }
            case let .failure(reason):
                failed(reason)
            }
        }
    }

    // MARK: - Contratar

    func contract() {
        guard state.operation == .idle, state.checkout == nil, let quote = state.quote else { return }
        guard !quote.isExpired else { failed(.quoteExpired); return }
        if contractQuoteID != quote.id {
            contractQuoteID = quote.id
            contractOperationID = UUID()
        }
        let operationID = contractOperationID ?? UUID()
        update { $0.operation = .reserving; $0.failure = nil }
        work = Task { [weak self] in
            guard let self else { return }
            switch await repository.reserve(quote: quote, operationID: operationID) {
            case let .success(snapshot):
                update { $0.checkout = snapshot; $0.operation = .idle }
            case let .failure(reason):
                failed(reason)
            }
        }
    }

    // MARK: - Helpers

    private func failed(_ reason: GuinchoFailureReason) {
        update {
            $0.failure = reason
            $0.operation = .idle
            if [.quoteExpired, .quoteConflict, .providerUnavailable].contains(reason) { $0.quote = nil }
        }
    }

    private func update(_ mutate: (inout GuinchoMapState) -> Void) {
        mutate(&state)
    }
}
