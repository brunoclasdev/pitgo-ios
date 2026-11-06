import Combine
import Foundation
import Supabase

@MainActor
final class PasswordRecoveryViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published var confirmation = ""
    @Published private(set) var busy = false
    @Published private(set) var message: String?
    private let client: SupabaseClient
    private var task: Task<Void, Never>?
    static var redirectURL: URL { URL(string: "\(Bundle.main.bundleIdentifier!).auth://auth/recovery")! }
    init(client: SupabaseClient) { self.client = client }
    deinit { task?.cancel() }

    func request() {
        guard !busy else { return }
        let email = SignUpValidation.normalizeEmail(email)
        guard SignUpValidation.isValidEmail(email) else { message = "Informe um e-mail válido."; return }
        busy = true
        task = Task { [weak self] in
            guard let self else { return }
            defer { busy = false }
            do {
                try await client.auth.resetPasswordForEmail(email, redirectTo: Self.redirectURL)
                message = "Se houver uma conta com esse e-mail, você receberá um link para redefinir sua senha."
            } catch { message = "Não foi possível enviar agora. Aguarde um momento, confira sua conexão e tente novamente." }
        }
    }

    func update(sessionStore: SessionStore) {
        guard !busy else { return }
        guard password.count >= 8 else { message = "A senha deve ter no mínimo 8 caracteres."; return }
        guard password == confirmation else { message = "As senhas não coincidem."; return }
        busy = true
        task = Task { [weak self] in
            guard let self else { return }
            defer { busy = false; password = ""; confirmation = "" }
            do {
                try await sessionStore.completePasswordRecovery(password: password)
            } catch { message = "Não foi possível alterar a senha. O link pode ter expirado. Solicite um novo link e tente novamente." }
        }
    }
}
