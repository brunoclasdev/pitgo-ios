//
//  ViaCepAddressLookupRepository.swift
//  pitgo
//
//  Fronteira exclusiva com o ViaCEP (`011` — busca de endereço por CEP). `URLSession` dedicada, sem
//  Authorization/cookies/cache/retry automático e sem qualquer dado do cadastro além do CEP na URL
//  (FR-016). Nenhum `Error` bruto, status HTTP, URL ou corpo de resposta chega ao ViewModel/log —
//  somente o resultado de domínio sanitizado (data-model.md "PostalCodeLookupResult").
//

import Foundation

final class ViaCepAddressLookupRepository {
    private static let host = "viacep.com.br"
    private static let requestTimeout: TimeInterval = 2.5

    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Self.requestTimeout
        configuration.timeoutIntervalForResource = Self.requestTimeout
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    /// `postalCode` já deve estar normalizado para exatamente 8 dígitos — a responsabilidade de
    /// validar o formato antes de consultar é do ViewModel (FR-003).
    func lookup(postalCode: String) async -> PostalCodeLookupResult {
        guard postalCode.count == 8, postalCode.allSatisfy(\.isNumber) else {
            return .failure(.unexpectedResponse)
        }
        guard var components = URLComponents() as URLComponents? else {
            return .failure(.unexpectedResponse)
        }
        components.scheme = "https"
        components.host = Self.host
        components.path = "/ws/\(postalCode)/json/"
        guard let url = components.url else {
            return .failure(.unexpectedResponse)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            return .failure(.unexpectedResponse)
        } catch let urlError as URLError {
            if Task.isCancelled { return .failure(.unexpectedResponse) }
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return .failure(.offline)
            case .timedOut:
                return .failure(.timeout)
            case .cancelled:
                return .failure(.unexpectedResponse)
            default:
                return .failure(.serviceUnavailable)
            }
        } catch {
            return .failure(.unexpectedResponse)
        }

        guard let http = response as? HTTPURLResponse else {
            return .failure(.unexpectedResponse)
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            return http.statusCode >= 500 ? .failure(.serviceUnavailable) : .failure(.unexpectedResponse)
        }

        guard let dto = try? JSONDecoder().decode(ViaCepResponseDTO.self, from: data) else {
            return .failure(.unexpectedResponse)
        }

        if dto.erro {
            return .notFound
        }

        guard let city = dto.localidade?.trimmed, !city.isEmpty,
              let ufValue = dto.uf?.trimmed, let state = BrazilianState(rawValue: ufValue.uppercased()) else {
            return .failure(.unexpectedResponse)
        }

        let result = PostalAddressResult(
            postalCode: postalCode,
            street: dto.logradouro?.trimmed.nilIfEmpty,
            complement: dto.complemento?.trimmed.nilIfEmpty,
            neighborhood: dto.bairro?.trimmed.nilIfEmpty,
            city: city,
            state: state
        )
        return .found(result)
    }
}

/// DTO privado do ViaCEP — tolerante a `erro` vindo como bool ou como string ("true"/"false"), pois
/// o formato JSON do serviço já variou entre versões. Campos administrativos (`unidade`, `ibge`,
/// `gia`, `ddd`, `siafi`, `regiao`) são propositalmente ignorados (FR-015).
private struct ViaCepResponseDTO: Decodable {
    let logradouro: String?
    let complemento: String?
    let bairro: String?
    let localidade: String?
    let uf: String?
    let erro: Bool

    private enum CodingKeys: String, CodingKey {
        case logradouro, complemento, bairro, localidade, uf, erro
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        logradouro = try container.decodeIfPresent(String.self, forKey: .logradouro)
        complemento = try container.decodeIfPresent(String.self, forKey: .complemento)
        bairro = try container.decodeIfPresent(String.self, forKey: .bairro)
        localidade = try container.decodeIfPresent(String.self, forKey: .localidade)
        uf = try container.decodeIfPresent(String.self, forKey: .uf)

        if let boolValue = try? container.decodeIfPresent(Bool.self, forKey: .erro) {
            erro = boolValue
        } else if let stringValue = try? container.decodeIfPresent(String.self, forKey: .erro) {
            erro = stringValue.lowercased() == "true"
        } else {
            erro = false
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
