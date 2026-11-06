import Supabase
import SwiftUI

struct BasicRegistrationView: View {
    @StateObject private var viewModel: BasicRegistrationViewModel
    @State private var showingPhoneCountries = false
    let onAuthenticated: (UUID) -> Void
    init(client: SupabaseClient, mode: AccountType, onAuthenticated: @escaping (UUID) -> Void) {
        _viewModel = StateObject(wrappedValue: BasicRegistrationViewModel(client: client, mode: mode))
        self.onAuthenticated = onAuthenticated
    }
    var body: some View {
        Form {
            Section("Crie sua conta") {
                TextField("Nome", text: $viewModel.firstName).textContentType(.givenName)
                TextField("Sobrenome", text: $viewModel.lastName).textContentType(.familyName)
                TextField("E-mail", text: $viewModel.email).textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                HStack(spacing: 12) {
                    Button { showingPhoneCountries = true } label: {
                        HStack(spacing: 4) {
                            Text("\(viewModel.phoneCountry.flag) \(viewModel.phoneCountry.callingCode)")
                            Image(systemName: "chevron.down").font(.caption2)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Código do país: \(viewModel.phoneCountry.name), \(viewModel.phoneCountry.callingCode)")
                    .accessibilityHint("Escolher país do telefone")
                    Divider()
                    TextField("Telefone", text: Binding(
                        get: { viewModel.phone },
                        set: { viewModel.updatePhone($0) }
                    ))
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
                }
                if viewModel.allowsCPF {
                    Picker("Tipo de pessoa", selection: Binding(
                        get: { viewModel.personType },
                        set: { viewModel.selectPersonType($0) }
                    )) {
                        Text("Pessoa física (CPF)").tag(PersonType.individual)
                        Text("Pessoa jurídica (CNPJ)").tag(PersonType.company)
                    }
                }
                TextField(String(localized: viewModel.personType.documentLabel), text: Binding(
                    get: {
                        viewModel.personType == .company
                            ? SignUpValidation.formatCNPJ(viewModel.document)
                            : SignUpValidation.formatCPF(viewModel.document)
                    },
                    set: { viewModel.updateDocument($0) }
                ))
                .keyboardType(viewModel.personType == .company ? .asciiCapable : .numberPad)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                SecureField("Senha (mínimo de 8 caracteres)", text: $viewModel.password).textContentType(.newPassword)
                SecureField("Confirmar senha", text: $viewModel.confirmation).textContentType(.newPassword)
            }
            Section {
                Text("Depois, complete seus dados e envie seus documentos. O acesso aos serviços depende da aprovação da equipe PitGo.")
                if let message = viewModel.message { Text(message).accessibilityAddTraits(.updatesFrequently) }
                if viewModel.busy { ProgressView("Criando conta…") }
                Button("Criar conta") { viewModel.submit() }
            }
        }
        .disabled(viewModel.busy)
        .navigationTitle("Criar conta")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPhoneCountries) {
            PhoneCountryPicker(countries: viewModel.phoneInput.countries, selection: viewModel.phoneCountry) { country in
                viewModel.selectPhoneCountry(country)
            }
        }
        .onChange(of: viewModel.completedUserID) { id in if let id { onAuthenticated(id) } }
    }
}

private struct PhoneCountryPicker: View {
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    let countries: [PhoneCountry]
    let selection: PhoneCountry
    let onSelect: (PhoneCountry) -> Void

    private var filteredCountries: [PhoneCountry] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return countries.filter {
            query.isEmpty || $0.name.localizedStandardContains(query)
                || $0.callingCode.contains(query) || $0.id.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List(filteredCountries) { country in
                Button {
                    onSelect(country)
                    dismiss()
                } label: {
                    HStack {
                        Text(country.flag)
                        Text(country.name).foregroundStyle(.primary)
                        Spacer()
                        Text(country.callingCode).foregroundStyle(.secondary)
                        if country.id == selection.id {
                            Image(systemName: "checkmark").accessibilityLabel("Selecionado")
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "País ou código")
            .navigationTitle("Código do país")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
        }
    }
}
