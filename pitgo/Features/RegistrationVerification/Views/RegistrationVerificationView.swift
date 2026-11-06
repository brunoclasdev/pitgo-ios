import Supabase
import SwiftUI

struct RegistrationVerificationView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @StateObject private var viewModel: RegistrationVerificationViewModel
    @State private var complementPresented = false
    @State private var kind: ProviderKind = .guincho
    private let client: SupabaseClient
    private let identity: AuthIdentity
    private let mode: AccountType
    let onClose: (() -> Void)?

    init(client: SupabaseClient, identity: AuthIdentity, mode: AccountType, onClose: (() -> Void)? = nil) {
        self.client = client
        self.identity = identity
        self.mode = mode
        self.onClose = onClose
        _viewModel = StateObject(wrappedValue: RegistrationVerificationViewModel(mode: mode, repository: RegistrationVerificationRepository(client: client)))
    }

    var body: some View {
        List {
            Section {
                Text(viewModel.registration?.status?.title ?? "Seu cadastro")
                    .font(.title2.bold())
                Text("O uso como \(mode == .client ? "cliente" : "prestador") depende da aprovação da equipe PitGo.")
                if viewModel.busy { ProgressView("Aguarde…") }
                if let error = viewModel.error { Text(error).foregroundStyle(.red).accessibilityAddTraits(.updatesFrequently) }
                Button("Atualizar situação") { viewModel.refresh() }
                if viewModel.registration?.status == .approved {
                    Button("Continuar") { onClose?(); Task { await sessionStore.selectMode(mode) } }
                }
            }
            if let registration = viewModel.registration {
                if registration.status == .inReview {
                    Section { Text("Recebemos seus dados e documentos. Aguarde a análise. Você pode atualizar a situação para consultar o resultado.") }
                }
                if registration.status == .correctionRequested {
                    Section("Pendências da análise") {
                        if let review = registration.reviews.first {
                            if let reason = review.reason { Text(reason) }
                            ForEach(review.correction_items, id: \.self) { Text(pendingTitle($0)) }
                        }
                        if !registration.editable {
                            Button("Corrigir cadastro") { viewModel.correct() }
                        }
                    }
                }
                if registration.editable {
                    Section("Dados complementares") {
                        if mode == .provider {
                            Picker("Modalidade", selection: $kind) {
                                Text("Guincho").tag(ProviderKind.guincho)
                                Text("PitTec").tag(ProviderKind.pittec)
                                Text("Loja").tag(ProviderKind.store)
                            }
                        }
                        Button(mode == .client ? "Preencher endereço" : "Preencher dados da empresa e serviços") { complementPresented = true }
                        Button("Confirmar dados já salvos") { viewModel.syncComplement() }
                    }.disabled(viewModel.pendingUpload)
                    if mode == .provider {
                        RegistrationVehiclesSection(registration: registration, onSave: viewModel.saveVehicles)
                    }
                    Section("Documentos pessoais") {
                        ForEach(RegistrationDocumentKind.allCases.filter { $0 != .vehicleDocument }, id: \.self) { kind in
                            documentRow(kind, vehicle: nil, registration: registration)
                        }
                    }
                    if mode == .provider {
                        ForEach(registration.vehicles.indices, id: \.self) { index in
                            let vehicle = registration.vehicles[index]
                            if let value = vehicle["id"]?.stringValue, let id = UUID(uuidString: value) {
                                Section("Documento — \(vehicle["plate"]?.stringValue ?? "veículo")") {
                                    documentRow(.vehicleDocument, vehicle: id, registration: registration)
                                }
                            }
                        }
                    }
                    if viewModel.pendingUpload {
                        Section {
                            Text("Há uma foto com envio pendente. Conclua o envio antes de continuar.")
                            Button("Tentar enviar novamente") { viewModel.retryUpload() }
                            Button("Descartar envio pendente", role: .destructive) { viewModel.discardPendingUpload() }
                        }
                    }
                    if !registration.pending_items.isEmpty {
                        Section("Falta completar") {
                            ForEach(Array(registration.pending_items.enumerated()), id: \.offset) { Text(pendingTitle($0.element)) }
                        }
                    }
                    Section {
                        Button("Enviar cadastro para análise") { viewModel.submit() }
                            .disabled(!registration.pending_items.isEmpty || viewModel.pendingUpload)
                    }
                }
            }
            Section {
                if let onClose { Button("Voltar", action: onClose) }
                Button("Sair", role: .destructive) { Task { await sessionStore.signOut() } }
            }
        }
        .disabled(viewModel.busy)
        .navigationTitle("Cadastro \(mode == .client ? "de cliente" : "de prestador")")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            kind = ProviderKind(rawValue: UserDefaults.standard.string(forKey: "pitgo.pendingProviderKind.\(identity.userID.uuidString)") ?? "") ?? .guincho
            viewModel.refresh()
        }
        .sheet(isPresented: $complementPresented, onDismiss: { viewModel.refresh() }) {
            NavigationStack {
                Group {
                    if mode == .client {
                        ClientAddressView(repository: ClientAddressRepository(client: client), locationRepository: DeviceLocationRepository(), onFinished: {
                            complementPresented = false
                            viewModel.syncComplement()
                        }, onSessionExpired: { Task { await sessionStore.signOut() } })
                    } else {
                        ProviderRegistrationView(repository: ProviderRegistrationRepository(client: client), verificationRepository: ProviderAddressVerificationRepository(client: client), accountID: identity.userID, authEmail: identity.authEmail, providerKind: kind, onFinished: {
                            complementPresented = false
                            viewModel.syncComplement()
                        }, onSessionExpired: { Task { await sessionStore.signOut() } })
                    }
                }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fechar") { complementPresented = false } } }
            }
        }
        .fullScreenCover(isPresented: $viewModel.cameraPresented) {
            RegistrationDocumentCamera(frontCamera: viewModel.selectedKind == .selfie || viewModel.selectedKind == .selfieWithDocument, onCapture: viewModel.captured, onCancel: { viewModel.cameraPresented = false })
                .ignoresSafeArea()
        }
        .sheet(isPresented: Binding(get: { viewModel.preview != nil }, set: { if !$0 { viewModel.closePreview() } })) {
            NavigationStack {
                VStack(spacing: 20) {
                    if let image = viewModel.preview { Image(uiImage: image).resizable().scaledToFit().accessibilityLabel("Foto do documento") }
                    if viewModel.isCapturePreview {
                        Text("Confira o enquadramento e a legibilidade antes de enviar.")
                        Button("Confirmar e enviar foto") { viewModel.confirmPhoto() }.buttonStyle(.borderedProminent)
                    }
                    Button("Fechar") { viewModel.closePreview() }
                }.padding().navigationTitle("Revisar foto")
            }
        }
    }

    private func documentRow(_ kind: RegistrationDocumentKind, vehicle: UUID?, registration: RegistrationCase) -> some View {
        let evidence = registration.evidence.first { $0.kind == kind && $0.vehicle_reference_id == vehicle && $0.upload_state == "RECEIVED" }
        return VStack(alignment: .leading, spacing: 8) {
            Label(kind.title, systemImage: evidence == nil ? "camera" : "checkmark.circle")
            Text(kind.guidance).font(.caption)
            if let evidence {
                Text("Foto recebida").font(.caption)
                Button("Ver \(kind.title)") { viewModel.showPhoto(evidence) }
            }
            Button(evidence == nil ? "Fotografar \(kind.title)" : "Substituir \(kind.title)") { viewModel.requestCamera(kind: kind, vehicle: vehicle) }
                .disabled(viewModel.pendingUpload)
            if viewModel.cameraDenied, let url = URL(string: UIApplication.openSettingsURLString) { Link("Abrir Ajustes", destination: url) }
        }.padding(.vertical, 4)
    }

    private func pendingTitle(_ value: String) -> String {
        if let kind = RegistrationDocumentKind(rawValue: value) { return kind.title }
        if value.hasPrefix("VEHICLE_DOCUMENT") { return "Documento de veículo pendente" }
        switch value {
        case "ADDRESS": return "Endereço completo"
        case "PROVIDER": return "Dados da empresa"
        case "OFFERS": return "Serviços oferecidos"
        case "VEHICLES": return "Veículos de atendimento"
        default: return "Confira os dados complementares e documentos do cadastro."
        }
    }
}

private struct RegistrationVehiclesSection: View {
    let registration: RegistrationCase
    let onSave: ([[String: AnyJSON]]) -> Void
    @State private var plate = ""
    @State private var make = ""
    @State private var model = ""
    @State private var color = ""

    var body: some View {
        Section("Veículos de atendimento") {
            Text("Cadastre cada veículo usado no atendimento e envie seu documento. Clientes não precisam enviar documentos de veículos.")
            ForEach(registration.vehicles.indices, id: \.self) { index in
                let vehicle = registration.vehicles[index]
                HStack {
                    Text(["plate", "make", "model", "color"].compactMap { vehicle[$0]?.stringValue }.joined(separator: " · "))
                    Spacer()
                    Button("Remover", role: .destructive) { onSave(registration.vehicles.enumerated().filter { $0.offset != index }.map(\.element)) }
                }
            }
            TextField("Placa", text: $plate).textInputAutocapitalization(.characters)
            TextField("Marca", text: $make)
            TextField("Modelo", text: $model)
            TextField("Cor", text: $color)
            Button("Adicionar veículo") {
                let vehicle: [String: AnyJSON] = ["id": .string(UUID().uuidString), "plate": .string(plate.uppercased().filter { $0.isLetter || $0.isNumber }), "make": .string(make.trimmingCharacters(in: .whitespaces)), "model": .string(model.trimmingCharacters(in: .whitespaces)), "color": .string(color.trimmingCharacters(in: .whitespaces))]
                onSave(registration.vehicles + [vehicle])
            }.disabled([plate, make, model, color].contains { $0.trimmingCharacters(in: .whitespaces).isEmpty })
        }
    }
}

private struct RegistrationDocumentCamera: UIViewControllerRepresentable {
    let frontCamera: Bool
    let onCapture: (UIImage) -> Void
    let onCancel: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture, onCancel: onCancel) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        if frontCamera && UIImagePickerController.isCameraDeviceAvailable(.front) { picker.cameraDevice = .front }
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void
        let onCancel: () -> Void
        init(onCapture: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) { self.onCapture = onCapture; self.onCancel = onCancel }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { onCapture(image) } else { onCancel() }
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onCancel() }
    }
}
