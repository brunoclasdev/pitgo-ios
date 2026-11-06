import Supabase
import SwiftUI

struct PasswordRecoveryView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @StateObject private var viewModel: PasswordRecoveryViewModel
    let validRecoverySession: Bool?
    init(client: SupabaseClient, validRecoverySession: Bool? = nil) {
        _viewModel = StateObject(wrappedValue: PasswordRecoveryViewModel(client: client))
        self.validRecoverySession = validRecoverySession
    }
    var body: some View {
        Form {
            if validRecoverySession == true {
                Section("Nova senha") {
                    SecureField("Senha (mínimo de 8 caracteres)", text: $viewModel.password).textContentType(.newPassword)
                    SecureField("Confirmar senha", text: $viewModel.confirmation).textContentType(.newPassword)
                    Button("Salvar nova senha") { viewModel.update(sessionStore: sessionStore) }
                }
            } else {
                Section {
                    if validRecoverySession == false { Text("Link inválido ou expirado. Solicite outro link para continuar.") }
                    TextField("E-mail", text: $viewModel.email).textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Enviar link de recuperação") { viewModel.request() }
                }
            }
            if viewModel.busy { ProgressView("Aguarde…") }
            if let message = viewModel.message { Text(message).accessibilityAddTraits(.updatesFrequently) }
            if validRecoverySession != nil {
                Button("Voltar para entrar") { Task { await sessionStore.signOut() } }
            }
        }
        .disabled(viewModel.busy)
        .navigationTitle("Recuperar senha")
        .navigationBarTitleDisplayMode(.inline)
    }
}
