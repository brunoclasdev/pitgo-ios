//
//  SupabaseClientProvider.swift
//  pitgo
//
//  Fronteira única de acesso ao `SupabaseClient` do app (ver contracts/supabase-configuration.md).
//  `SUPABASE_URL`/`SUPABASE_KEY` já foram validados em tempo de build pelo Run Script
//  `Scripts/validate-supabase-config.sh` — esta leitura runtime nunca precisa revalidar o
//  conteúdo, apenas materializar o cliente.
//

import Foundation
import Supabase

enum SupabaseClientProvider {
    static let client: SupabaseClient = {
        guard
            let urlString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
            let url = URL(string: urlString),
            let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_KEY") as? String
        else {
            preconditionFailure(
                "Supabase configuration missing at runtime — build validation should have prevented this."
            )
        }
        return SupabaseClient(supabaseURL: url, supabaseKey: key)
    }()
}
