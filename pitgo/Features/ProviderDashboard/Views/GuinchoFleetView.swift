import SwiftUI
import Supabase

struct GuinchoFleetVehicle: Decodable, Identifiable {
    let id: UUID
    let plate: String
    let make: String
    let model: String
    let color: String
    let revision: Int64
    let guincho_size_id: UUID?
    let selected: Bool
}

struct GuinchoFleetView: View {
    let client: SupabaseClient
    @Environment(\.pitGoTokens) private var tokens
    @State private var vehicles: [GuinchoFleetVehicle] = []
    @State private var sizes: [GuinchoSize] = []
    @State private var editingID: UUID?
    @State private var plate = ""
    @State private var make = ""
    @State private var model = ""
    @State private var color = ""
    @State private var sizeID: UUID?
    @State private var busy = false
    @State private var message: String?
    @State private var requestID = UUID()

    var body: some View {
        Form {
            Section("Veículos de atendimento") {
                ForEach(vehicles) { vehicle in
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(vehicle.make) \(vehicle.model) · \(vehicle.plate)")
                        Text(sizes.first { $0.id == vehicle.guincho_size_id }?.name ?? "Complete o porte para receber solicitações")
                            .font(.caption)
                        if vehicle.selected { Label("Selecionado para atendimento", systemImage: "checkmark.circle") }
                        Button("Editar veículo") {
                            editingID = vehicle.id; plate = vehicle.plate; make = vehicle.make
                            model = vehicle.model; color = vehicle.color; sizeID = vehicle.guincho_size_id
                        }
                        Button("Usar este guincho") { Task { await select(vehicle) } }
                            .disabled(vehicle.guincho_size_id == nil || vehicle.selected)
                    }
                }
            }
            Section(editingID == nil ? "Cadastrar guincho" : "Editar guincho") {
                TextField("Placa", text: $plate).textInputAutocapitalization(.characters)
                VehicleMakePicker(selection: $make)
                TextField("Modelo", text: $model)
                TextField("Cor", text: $color)
                Picker("Tipo/porte", selection: $sizeID) {
                    Text("Selecionar porte").tag(UUID?.none)
                    ForEach(sizes) { Text($0.name).tag(Optional($0.id)) }
                }
                Button("Salvar veículo") { Task { await save() } }.disabled(!valid)
                if editingID != nil { Button("Cancelar edição") { clear() } }
            }
            if let message { Text(message).foregroundStyle(tokens.accent) }
            Button("Atualizar") { Task { await load() } }
        }
        .disabled(busy)
        .overlay { if busy { ProgressView() } }
        .navigationTitle("Meus guinchos")
        .onChange(of: [plate, make, model, color, sizeID?.uuidString ?? ""]) { _ in requestID = UUID() }
        .task { await load() }
    }

    private var valid: Bool {
        plate.uppercased().filter { $0.isLetter || $0.isNumber }.range(of: "^[A-Z]{3}[0-9][A-Z0-9][0-9]{2}$", options: .regularExpression) != nil
            && [make, model, color].allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            && sizes.contains { $0.id == sizeID }
    }
    private func clear() {
        editingID = nil; plate = ""; make = ""; model = ""; color = ""; sizeID = nil; requestID = UUID()
    }
    private func load() async {
        busy = true
        do {
            let catalog: TransportCatalog = try await client.rpc("get_guincho_transport_catalog").execute().value
            let fleet: [GuinchoFleetVehicle] = try await client.rpc("get_my_guincho_vehicles").execute().value
            sizes = catalog.sizes; vehicles = fleet; message = nil
        } catch { message = "Não foi possível carregar os guinchos. Tente novamente." }
        busy = false
    }
    private func select(_ vehicle: GuinchoFleetVehicle) async {
        struct Params: Encodable { let p_vehicle_id: UUID; let p_request_id: UUID }
        busy = true
        do {
            try await client.rpc("select_my_guincho_dispatch_vehicle", params: Params(p_vehicle_id: vehicle.id, p_request_id: requestID)).execute()
            requestID = UUID()
            await load()
        } catch { message = "Não foi possível selecionar. Atualize o cadastro e tente novamente." }
        busy = false
    }
    private func save() async {
        guard valid, let sizeID else { return }
        busy = true
        let normalizedPlate = plate.uppercased().filter { $0.isLetter || $0.isNumber }
        do {
            if let vehicle = vehicles.first(where: { $0.id == editingID }) {
                struct Payload: Encodable { let plate: String; let make: String; let model: String; let color: String; let guincho_size_id: UUID }
                struct Params: Encodable { let p_vehicle_id: UUID; let p_expected_revision: Int64; let p_vehicle: Payload }
                try await client.rpc("update_my_guincho_vehicle", params: Params(p_vehicle_id: vehicle.id, p_expected_revision: vehicle.revision,
                    p_vehicle: Payload(plate: normalizedPlate, make: make.trimmingCharacters(in: .whitespacesAndNewlines), model: model.trimmingCharacters(in: .whitespacesAndNewlines), color: color.trimmingCharacters(in: .whitespacesAndNewlines), guincho_size_id: sizeID))).execute()
            } else {
                struct Params: Encodable { let p_request_id: UUID; let p_plate: String; let p_make: String; let p_model: String; let p_color: String; let p_size_id: UUID }
                try await client.rpc("register_my_guincho_vehicle", params: Params(p_request_id: requestID, p_plate: normalizedPlate,
                    p_make: make.trimmingCharacters(in: .whitespacesAndNewlines), p_model: model.trimmingCharacters(in: .whitespacesAndNewlines), p_color: color.trimmingCharacters(in: .whitespacesAndNewlines), p_size_id: sizeID)).execute()
            }
            clear()
            await load()
        } catch let error as PostgrestError where error.code == "40001" {
            message = "O cadastro mudou em outro dispositivo. Atualize antes de salvar novamente."
        } catch { message = "Não foi possível salvar. Confira os dados e tente novamente." }
        busy = false
    }
}
