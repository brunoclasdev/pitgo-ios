import CoreLocation
import SwiftUI
import UIKit

enum ExternalNavigator: String, CaseIterable, Identifiable {
    case waze
    case googleMaps

    var id: String { rawValue }
    var title: String { self == .waze ? "Waze" : "Google Maps" }

    fileprivate var queryURL: URL? {
        URL(string: self == .waze ? "waze://" : "comgooglemaps://")
    }

    fileprivate func destinationURL(_ coordinate: CLLocationCoordinate2D) -> URL? {
        guard Self.isValid(coordinate) else { return nil }
        var components = URLComponents()
        components.scheme = self == .waze ? "waze" : "comgooglemaps"
        if self == .waze {
            components.queryItems = [
                URLQueryItem(name: "ll", value: "\(coordinate.latitude),\(coordinate.longitude)"),
                URLQueryItem(name: "navigate", value: "yes")
            ]
        } else {
            components.queryItems = [
                URLQueryItem(name: "daddr", value: "\(coordinate.latitude),\(coordinate.longitude)"),
                URLQueryItem(name: "directionsmode", value: "driving")
            ]
        }
        guard let query = components.percentEncodedQuery else { return nil }
        return URL(string: "\(components.scheme ?? "")://?\(query)")
    }

    static func isValid(_ coordinate: CLLocationCoordinate2D) -> Bool {
        coordinate.latitude.isFinite && coordinate.longitude.isFinite
            && (-90...90).contains(coordinate.latitude) && (-180...180).contains(coordinate.longitude)
    }
}

struct ExternalNavigatorOption: Identifiable {
    let navigator: ExternalNavigator
    let isAvailable: Bool
    var id: String { navigator.id }
}

@MainActor
enum ExternalNavigationLauncher {
    static func options() -> [ExternalNavigatorOption] {
        ExternalNavigator.allCases.map { navigator in
            ExternalNavigatorOption(navigator: navigator, isAvailable: canOpen(navigator))
        }
    }

    static func open(_ navigator: ExternalNavigator, destination: CLLocationCoordinate2D) async -> Bool {
        guard ExternalNavigator.isValid(destination), canOpen(navigator),
              let url = navigator.destinationURL(destination) else { return false }
        return await UIApplication.shared.open(url, options: [:])
    }

    private static func canOpen(_ navigator: ExternalNavigator) -> Bool {
        guard let url = navigator.queryURL else { return false }
        return UIApplication.shared.canOpenURL(url)
    }
}

/// Opções explícitas. A autorização e o destino são relidos tanto antes de mostrar a lista quanto
/// depois da escolha; uma falha abre uma mensagem recuperável sem trocar de navegador.
struct ExternalNavigationButton: View {
    let resolveDestination: () async -> CLLocationCoordinate2D?

    @State private var options: [ExternalNavigatorOption] = []
    @State private var isChoosing = false
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        Button {
            prepareChoices()
        } label: {
            if isWorking {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 44)
            } else {
                Label("Abrir navegação", systemImage: "arrow.triangle.turn.up.right.diamond")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .disabled(isWorking)
        .confirmationDialog("Escolha o aplicativo de navegação", isPresented: $isChoosing, titleVisibility: .visible) {
            ForEach(options) { option in
                Button(option.isAvailable ? option.navigator.title : "\(option.navigator.title) (não instalado)") {
                    launch(option.navigator)
                }
                .disabled(!option.isAvailable)
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text(options.contains(where: \.isAvailable)
                 ? "O aplicativo escolhido receberá somente o destino do atendimento."
                 : "Instale Waze ou Google Maps para abrir a navegação.")
        }
        .alert("Não foi possível abrir a navegação", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Tente novamente.")
        }
    }

    private func prepareChoices() {
        guard !isWorking else { return }
        isWorking = true
        Task { @MainActor in
            guard let _ = await resolveDestination() else {
                errorMessage = "O atendimento mudou ou o destino não está disponível. Atualize a tela e tente novamente."
                isWorking = false
                return
            }
            options = ExternalNavigationLauncher.options()
            isChoosing = true
            isWorking = false
        }
    }

    private func launch(_ navigator: ExternalNavigator) {
        guard !isWorking else { return }
        isChoosing = false
        isWorking = true
        Task { @MainActor in
            guard let destination = await resolveDestination() else {
                errorMessage = "O atendimento mudou ou o destino não está disponível. Atualize a tela e tente novamente."
                isWorking = false
                return
            }
            guard await ExternalNavigationLauncher.open(navigator, destination: destination) else {
                options = ExternalNavigationLauncher.options()
                errorMessage = "O aplicativo escolhido não está disponível. Escolha novamente um navegador instalado."
                isWorking = false
                return
            }
            isWorking = false
        }
    }
}
