//
//  ConnectivityObserver.swift
//  pitgo
//
//  Observação de conectividade com `NWPathMonitor` (`010` — Core/Map/Config §T008). Usada para
//  distinguir proativamente "sem rede" de outras falhas de mapa/RPC, sem esperar o timeout de uma
//  chamada de rede em andamento.
//

import Foundation
import Network

enum ConnectivityStatus: Equatable {
    case online
    case offline
}

@Observable
@MainActor
final class ConnectivityObserver {
    private(set) var status: ConnectivityStatus = .online

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.pitgo.connectivity-observer")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let newStatus: ConnectivityStatus = path.status == .satisfied ? .online : .offline
            Task { @MainActor [weak self] in
                self?.status = newStatus
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
