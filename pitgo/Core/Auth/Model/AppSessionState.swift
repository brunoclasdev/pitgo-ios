//
//  AppSessionState.swift
//  pitgo
//
//  Estado raiz mutuamente exclusivo de sessão (ver data-model.md de `006`/`009`). Um papel de conta
//  autoritativo (`get_my_account_context()`, nunca `raw_user_meta_data`) decide entre os três estados
//  autenticados; qualquer papel ausente/ambíguo ou Provider inconsistente cai em `.blocked`. Somente
//  os três casos `.authenticated*` entregam dados renderizáveis; toda outra transição remove o
//  snapshot anterior.
//

import Foundation

enum UnauthenticatedReason {
    case loggedOut
    case sessionInvalid
}

enum AppSessionState {
    case passwordRecovery(valid: Bool)
    case registrationRequired(AuthIdentity, AccountType)
    case initializing
    case verifying
    case unauthenticated(reason: UnauthenticatedReason?)
    case offlineVerification
    case blocked(reason: BlockedReason)
    case authenticatedClient(AccountSnapshot)
    case authenticatedProviderOnboarding(AuthIdentity)
    case authenticatedProviderReady(ProviderSnapshot)
}
