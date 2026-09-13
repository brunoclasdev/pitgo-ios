//
//  UnauthenticatedRoute.swift
//  pitgo
//
//  Rotas empilhadas dentro do fluxo não autenticado (Welcome raiz). Ver
//  contracts/account-registration.md (005), contracts/navigation.md (006) e
//  contracts/navigation-session.md (009).
//
//  `SignUpOrigin` (introduzido em `007`) foi removido em `009` — o CTA de empresa agora usa
//  `.providerSignUp`, nunca o SignUp de cliente (ver research.md §2 de `009`).
//

import Foundation

enum UnauthenticatedRoute: Hashable {
    case signUp
    case providerSignUp
    case login
}
