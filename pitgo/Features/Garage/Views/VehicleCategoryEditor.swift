import SwiftUI

struct VehicleCategoryEditor: View {
    let vehicle: Vehicle
    let repository: VehicleRepository
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var categories: [TransportCategory] = []
    @State private var selected: UUID?
    @State private var busy = false
    @State private var failed = false

    var body: some View {
        Form {
            Text("\(vehicle.brand) \(vehicle.model)")
            Picker("Categoria para transporte", selection: $selected) {
                Text("Selecionar").tag(UUID?.none)
                ForEach(categories) { Text($0.name).tag(Optional($0.id)) }
            }
            if failed { Text("Não foi possível atualizar. Tente novamente.").foregroundStyle(.red) }
            Button("Recarregar categorias") { Task { await load() } }.disabled(busy)
            Button("Salvar") {
                guard let selected else { return }
                busy = true
                Task {
                    do {
                        try await repository.classifyVehicle(vehicle.id, categoryID: selected)
                        onSaved()
                        dismiss()
                    } catch { failed = true }
                    busy = false
                }
            }.disabled(busy || selected == nil)
        }
        .navigationTitle("Categoria do veículo")
        .task { selected = vehicle.transportCategoryID; await load() }
    }
    private func load() async {
        busy = true
        do { categories = try await repository.transportCatalog().vehicle_categories; failed = false }
        catch { failed = true }
        busy = false
    }
}
