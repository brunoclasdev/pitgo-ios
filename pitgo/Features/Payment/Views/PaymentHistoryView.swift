import SwiftUI

struct PaymentHistoryView: View {
    let repository: PaymentRepository
    @State private var payments: [PaymentHistoryRecord] = []
    @State private var loading = false
    @State private var hasMore = true
    @State private var error: String?

    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red) }
            if payments.isEmpty && !loading && error == nil { Text("Nenhum pagamento encontrado.") }
            ForEach(payments) { payment in
                VStack(alignment: .leading, spacing: 6) {
                    Text(payment.amount, format: .currency(code: "BRL")).font(.headline)
                    Text(payment.statusLabel)
                    Text(payment.method == .pix ? "Pix" : "Cartão \(payment.cardBrand ?? "") •••• \(payment.cardLastFourDigits ?? "")")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if let date = payment.createdAt {
                        Text(date, format: .dateTime.day().month().year().hour().minute()).font(.caption).foregroundStyle(.secondary)
                    }
                    if payment.supportRequired { Text("Este pagamento precisa de atendimento do suporte.").font(.caption) }
                }.padding(.vertical, 4)
            }
            if loading { ProgressView().frame(maxWidth: .infinity) }
            if hasMore && !loading { Button(error == nil ? "Carregar mais" : "Tentar novamente") { Task { await load(reset: false) } } }
        }
        .navigationTitle("Histórico de pagamentos")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load(reset: true) }
        .refreshable { await load(reset: true) }
    }

    @MainActor private func load(reset: Bool) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let rows = try await repository.history(before: reset ? nil : payments.last)
            if reset { payments = [] }
            let existing = Set(payments.map(\.id))
            payments.append(contentsOf: rows.filter { !existing.contains($0.id) })
            hasMore = rows.count == 20
            error = nil
        } catch { self.error = "Não foi possível carregar os pagamentos. Tente novamente." }
    }
}
