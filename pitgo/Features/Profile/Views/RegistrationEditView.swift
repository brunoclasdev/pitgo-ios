import SwiftUI
import Supabase

struct RegistrationAddress: Codable, Equatable {
    var street = ""
    var number = ""
    var neighborhood = ""
    var zip_code = ""
    var city = ""
    var state = ""
    var complement: String? = nil
    var updated_at: String? = nil

    var normalized: NormalizedAddress {
        NormalizedAddress(street: street.trimmingCharacters(in: .whitespacesAndNewlines), number: number.trimmingCharacters(in: .whitespacesAndNewlines),
            neighborhood: neighborhood.trimmingCharacters(in: .whitespacesAndNewlines), zipCode: zip_code.filter(\.isNumber),
            city: city.trimmingCharacters(in: .whitespacesAndNewlines), state: state.uppercased().trimmingCharacters(in: .whitespacesAndNewlines),
            country: "BR", complement: complement)
    }
    var valid: Bool {
        let value = normalized
        return !value.street.isEmpty && !value.number.isEmpty && !value.neighborhood.isEmpty && !value.city.isEmpty
            && value.zipCode.count == 8 && ["AC", "AL", "AP", "AM", "BA", "CE", "DF", "ES", "GO", "MA", "MT", "MS", "MG", "PA", "PB", "PR", "PE", "PI", "RJ", "RN", "RS", "RO", "RR", "SC", "SP", "SE", "TO"].contains(value.state)
    }
}

struct RegistrationSnapshot: Decodable {
    let owner_id: UUID
    let account_type: String
    let name: String
    let phone: String
    let email: String
    let document: String
    let description: String?
    let provider_kind: String?
    let updated_at: String
    let address: RegistrationAddress?
}

struct RegistrationEditView: View {
    let client: SupabaseClient
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sessionStore: SessionStore
    @State private var snapshot: RegistrationSnapshot?
    @State private var name = ""
    @State private var phone = ""
    @State private var description = ""
    @State private var address = RegistrationAddress()
    @State private var busy = false
    @State private var message: String?
    @State private var saved = false

    var body: some View {
        Form {
            if let snapshot {
                Section("Dados cadastrais") {
                    TextField("Nome", text: $name)
                    TextField("Telefone", text: $phone).keyboardType(.phonePad)
                    LabeledContent("E-mail", value: snapshot.email)
                    LabeledContent("Documento", value: snapshot.document)
                    if snapshot.account_type == "PROVIDER" {
                        TextField("Descrição", text: $description, axis: .vertical)
                    }
                }
                if snapshot.provider_kind == "GUINCHO" {
                    Section("Guincho") {
                        NavigationLink("Veículos e portes de atendimento") { GuinchoFleetView(client: client) }
                    }
                }
                Section("Endereço") {
                    TextField("CEP", text: $address.zip_code).keyboardType(.numberPad)
                    TextField("Rua", text: $address.street)
                    TextField("Número", text: $address.number)
                    TextField("Bairro", text: $address.neighborhood)
                    TextField("Cidade", text: $address.city)
                    TextField("UF", text: $address.state).textInputAutocapitalization(.characters)
                    TextField("Complemento", text: Binding(get: { address.complement ?? "" }, set: { address.complement = $0 }))
                }
                Button("Salvar alterações") { Task { await save() } }
                    .disabled(!valid)
            }
            if let message { Text(message).foregroundStyle(saved ? Color.green : Color.red) }
            Button(snapshot == nil ? "Carregar cadastro" : "Recarregar cadastro") { Task { await load() } }
        }
        .disabled(busy)
        .overlay { if busy { ProgressView() } }
        .navigationTitle("Editar cadastro")
        .task { await load() }
    }
    private var addressChanged: Bool { address != (snapshot?.address ?? RegistrationAddress()) }
    private var valid: Bool {
        (1...150).contains(name.trimmingCharacters(in: .whitespacesAndNewlines).count)
            && BrazilianInputValidation.isValidBrazilianPhone(phone.filter(\.isNumber)) && description.count <= 2000
            && (!addressChanged || address.valid)
    }
    private func load() async {
        busy = true
        do {
            let result: RegistrationSnapshot = try await client.rpc("get_my_registration").execute().value
            snapshot = result; name = result.name; phone = result.phone
            description = result.description ?? ""; address = result.address ?? RegistrationAddress(); message = nil
        } catch { handle(error) }
        busy = false
    }
    private func save() async {
        guard valid, let snapshot else { return }
        busy = true; message = nil
        var token: String?
        if addressChanged && snapshot.account_type == "PROVIDER" {
            switch await ProviderAddressVerificationRepository(client: client).verify(address: address.normalized) {
            case let .matched(value, _): token = value
            case .failure:
                message = "Não foi possível verificar o endereço. Confira os dados e tente novamente."
                busy = false
                return
            }
        }
        struct Params: Encodable {
            let p_expected_updated_at: String
            let p_name: String
            let p_phone: String
            let p_description: String
            let p_address: RegistrationAddress?
            let p_address_expected_updated_at: String?
            let p_verification_token: String?
        }
        do {
            let updated: RegistrationSnapshot = try await client.rpc("update_my_registration", params: Params(
                p_expected_updated_at: snapshot.updated_at, p_name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                p_phone: phone.filter(\.isNumber), p_description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                p_address: addressChanged ? address : nil, p_address_expected_updated_at: snapshot.address?.updated_at,
                p_verification_token: token)).execute().value
            self.snapshot = updated; name = updated.name; phone = updated.phone
            description = updated.description ?? ""; address = updated.address ?? RegistrationAddress()
            saved = true; message = "Cadastro atualizado."
            busy = false
            dismiss()
            await sessionStore.bootstrap()
            return
        } catch { handle(error) }
        busy = false
    }
    private func handle(_ error: Error) {
        if let error = error as? PostgrestError {
            switch error.code {
            case "40001": message = "O cadastro mudou em outro dispositivo. Recarregue antes de salvar novamente."
            case "42501": message = "Sua sessão expirou. Entre novamente."
            case "22023": message = "Confira os campos e o endereço informado."
            default: message = "Não foi possível atualizar o cadastro. Tente novamente."
            }
        } else { message = "Sem conexão. Seus dados permanecem no formulário. Tente novamente." }
    }
}
