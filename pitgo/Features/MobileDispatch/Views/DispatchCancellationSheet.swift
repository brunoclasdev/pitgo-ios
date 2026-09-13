//
//  DispatchCancellationSheet.swift
//  pitgo
//
//  `.sheet` rolável com motivo obrigatório (`TextEditor`), reutilizado por cliente e provider após o
//  aceite (contracts/mobile-dispatch-ui-navigation.md "Cancelamento"). Voltar/gesto não contorna o
//  motivo — só os botões desta View resolvem a apresentação.
//

import SwiftUI

struct DispatchCancellationSheet: View {
    @Environment(\.pitGoTokens) private var tokens
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @State private var showValidationError = false

    let isSubmitting: Bool
    let onConfirm: (String) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Por que você está cancelando?")
                        .font(PitGoTypography.categoryTitle)
                        .accessibilityAddTraits(.isHeader)

                    TextEditor(text: $reason)
                        .frame(minHeight: 120)
                        .padding(8)
                        .background(tokens.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(showValidationError ? Color.red : tokens.outline, lineWidth: 1)
                        )
                        .disabled(isSubmitting)
                        .accessibilityLabel("Motivo do cancelamento")

                    if showValidationError {
                        Text("Informe o motivo do cancelamento.")
                            .font(PitGoTypography.caption)
                            .foregroundStyle(.red)
                            .accessibilityAddTraits(.updatesFrequently)
                    }

                    Button(action: confirm) {
                        ZStack {
                            if isSubmitting { ProgressView().tint(.white) }
                            Text("Confirmar cancelamento").opacity(isSubmitting ? 0 : 1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    }
                    .foregroundStyle(.white)
                    .background(Color.red)
                    .clipShape(Capsule())
                    .frame(minHeight: 56)
                    .disabled(isSubmitting)
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(tokens.background)
            .navigationTitle("Cancelar atendimento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Voltar") { dismiss() }
                        .disabled(isSubmitting)
                }
            }
        }
    }

    private func confirm() {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showValidationError = true
            return
        }
        showValidationError = false
        onConfirm(trimmed)
    }
}
