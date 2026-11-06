import Combine
import Foundation
import Supabase

@MainActor
final class BasicRegistrationViewModel: ObservableObject {
    @Published var firstName = ""
    @Published var lastName = ""
    @Published var email = ""
    @Published private(set) var phone = ""
    @Published private(set) var phoneCountry: PhoneCountry
    let phoneInput = InternationalPhoneInput()
    @Published var document = ""
    @Published private(set) var personType: PersonType
    @Published var password = ""
    @Published var confirmation = ""
    @Published private(set) var busy = false
    @Published private(set) var message: String?
    @Published private(set) var completedUserID: UUID?
    private let client: SupabaseClient
    private let mode: AccountType
    private var task: Task<Void, Never>?
    init(client: SupabaseClient, mode: AccountType) {
        self.client = client
        self.mode = mode
        phoneCountry = phoneInput.countries.first { $0.id == "BR" }!
        personType = mode == .provider ? .company : .individual
    }

    func selectPhoneCountry(_ country: PhoneCountry) {
        guard !busy else { return }
        phoneCountry = country
        phone = phoneInput.format(phone, country: country)
        message = nil
    }

    func updatePhone(_ value: String) {
        guard !busy else { return }
        if let international = phoneInput.internationalInput(value) {
            phoneCountry = international.country
            phone = international.number
        } else {
            phone = phoneInput.format(value, country: phoneCountry)
        }
        message = nil
    }

    var allowsCPF: Bool { mode == .client }

    func selectPersonType(_ value: PersonType) {
        guard !busy, allowsCPF, value != personType else { return }
        personType = value
        document = ""
        message = nil
    }

    func updateDocument(_ value: String) {
        guard !busy else { return }
        document = String(SignUpValidation.normalizeDocument(value, personType: personType).prefix(personType.documentMaxLength))
    }
    deinit { task?.cancel() }

    func submit() {
        guard !busy else { return }
        let first = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = SignUpValidation.normalizeEmail(email)
        let document = SignUpValidation.normalizeDocument(document, personType: personType)
        let isCompany = personType == .company
        guard !first.isEmpty, !last.isEmpty else { message = "Informe nome e sobrenome."; return }
        guard SignUpValidation.isValidEmail(email) else { message = "Informe um e-mail válido."; return }
        guard let phone = phoneInput.e164(phone, country: phoneCountry) else {
            message = "Informe um telefone válido para \(phoneCountry.name), incluindo o código de área quando necessário."
            return
        }
        guard (isCompany ? SignUpValidation.isValidCNPJ(document) : allowsCPF && SignUpValidation.isValidCPF(document)) else {
            message = isCompany ? "Confira o CNPJ informado." : "Confira o CPF informado."
            return
        }
        guard password.count >= 8 else { message = "A senha deve ter no mínimo 8 caracteres."; return }
        guard password == confirmation else { message = "As senhas não coincidem."; return }
        busy = true
        message = nil
        let secret = password
        task = Task { [weak self] in
            guard let self else { return }
            defer { busy = false; password = ""; confirmation = "" }
            do {
                if let session = try? await client.auth.session, session.user.email?.lowercased() == email {
                    completedUserID = session.user.id
                    return
                }
                let result = try await client.auth.signUp(email: email, password: secret, data: [
                    "first_name": .string(first), "last_name": .string(last), "name": .string("\(first) \(last)"),
                    "phone": .string(phone), (isCompany ? "cnpj" : "cpf"): .string(document), "account_type": .string(mode.rawValue)
                ])
                guard let session = result.session else {
                    message = "Se o cadastro foi recebido, confirme o e-mail e entre para continuar. Se já possui conta, entre ou recupere sua senha."
                    return
                }
                completedUserID = session.user.id
            } catch is CancellationError { }
            catch {
                message = "Não foi possível concluir. Confira os dados e sua conexão. Se já possui conta, entre ou recupere sua senha."
            }
        }
    }
}
