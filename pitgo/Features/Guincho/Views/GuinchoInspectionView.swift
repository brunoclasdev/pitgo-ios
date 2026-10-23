import AVFoundation
import SwiftUI

struct GuinchoInspectionView: View {
    @Environment(\.pitGoTokens) private var tokens
    @StateObject private var viewModel: GuinchoInspectionViewModel
    @State private var showCamera = false
    @State private var showCorrection = false
    @State private var correctionReason = ""
    @State private var capturePoint: GuinchoInspectionPoint = .front
    @State private var selectedDetailPoint: GuinchoInspectionDetailPoint?
    @State private var replacingPhotoID: UUID?
    @State private var detailCaption = ""
    @State private var cameraMessage: String?
    @State private var showDiscardLostCapture = false
    @State private var selectedPhoto: GuinchoInspectionPhoto?
    let onSubmissionConfirmed: (() -> Void)?

    init(appointmentID: UUID, repository: GuinchoInspectionRepository, onSubmissionConfirmed: (() -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: GuinchoInspectionViewModel(appointmentID: appointmentID, repository: repository))
        self.onSubmissionConfirmed = onSubmissionConfirmed
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.document == nil {
                ProgressView("Carregando vistoria…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let document = viewModel.document {
                inspection(document)
            } else {
                VStack(spacing: 12) {
                    Text(viewModel.failure ?? "Vistoria indisponível.")
                    Button("Tentar novamente") { viewModel.load() }
                }.padding(24)
            }
        }
        .background(tokens.background)
        .navigationTitle("Vistoria do veículo")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel.load()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if !Task.isCancelled,
                   let document = viewModel.document,
                   (!document.isProvider || document.summary.state == .submitted) {
                    viewModel.refreshNow()
                }
            }
        }
        .onChange(of: viewModel.submissionConfirmedID) { operationID in
            guard operationID != nil else { return }
            onSubmissionConfirmed?()
            viewModel.consumeSubmissionConfirmation()
        }
        .alert("Câmera indisponível", isPresented: Binding(
            get: { cameraMessage != nil }, set: { if !$0 { cameraMessage = nil } }
        )) {
            Button("OK") { cameraMessage = nil }
        } message: { Text(cameraMessage ?? "") }
        .confirmationDialog("Descartar a captura irrecuperável?", isPresented: $showDiscardLostCapture, titleVisibility: .visible) {
            Button("Descartar e liberar o ponto", role: .destructive) { viewModel.discardUnrecoverableCapture() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Os arquivos desta captura não podem ser restaurados com segurança. O ponto ficará disponível para uma nova foto.")
        }
        .sheet(item: $selectedPhoto) { photo in
            NavigationStack {
                Group {
                    if let image = viewModel.enlargedImage {
                        ScrollView { Image(uiImage: image).resizable().scaledToFit().padding(12) }
                    } else if viewModel.isLoadingEnlargedImage {
                        ProgressView("Carregando foto…")
                    } else {
                        VStack(spacing: 12) {
                            Text(viewModel.failure ?? "Não foi possível carregar esta foto.")
                            Button("Tentar novamente") { viewModel.loadEnlargedImage(photo) }
                        }
                    }
                }
                .navigationTitle(photo.point.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fechar") { selectedPhoto = nil } } }
                .task { viewModel.loadEnlargedImage(photo) }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                GuinchoInspectionCamera(onCapture: { image in
                    showCamera = false
                    viewModel.capture(image, point: capturePoint,
                                      detailPoint: selectedDetailPoint?.rawValue,
                                      caption: capturePoint == .detail ? detailCaption : nil,
                                      replacing: replacingPhotoID)
                    replacingPhotoID = nil
                    selectedDetailPoint = nil
                }, onCancel: { showCamera = false })
                .ignoresSafeArea()
            } else {
                VStack(spacing: 12) {
                    Text("A câmera não está disponível neste dispositivo.")
                    Button("Fechar") { showCamera = false }
                }
            }
        }
        .sheet(isPresented: $showCorrection) {
            NavigationStack {
                Form {
                    Section("O que precisa ser corrigido?") {
                        TextField("Descreva o problema", text: $correctionReason, axis: .vertical)
                            .lineLimit(3...8)
                    }
                    Button("Solicitar correção") {
                        viewModel.requestCorrection(reason: correctionReason)
                        showCorrection = false
                    }
                    .disabled(correctionReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSaving)
                }
                .navigationTitle("Solicitar correção")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { showCorrection = false } } }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func inspection(_ document: GuinchoInspectionDocument) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let vehicle = document.vehicle, !vehicle.displayName.isEmpty {
                    Text(vehicle.displayName).font(PitGoTypography.categoryTitle)
                }
                Text(statusText(document.summary))
                    .font(PitGoTypography.body)
                    .accessibilityAddTraits(.updatesFrequently)
                if let reason = document.summary.correctionReason, !reason.isEmpty {
                    Text("Motivo da correção: \(reason)")
                        .font(PitGoTypography.body).foregroundStyle(tokens.textSecondary)
                }
                if let failure = viewModel.failure {
                    Text(failure).font(PitGoTypography.caption).foregroundStyle(.red)
                    if document.isProvider && document.summary.state == .draft && viewModel.hasPendingCapture {
                        Button("Tentar salvar novamente") { viewModel.retryPendingCapture() }
                            .disabled(viewModel.isSaving)
                    } else if document.isProvider && document.summary.state == .draft && viewModel.hasUnrecoverableCapture {
                        Button("Descartar captura perdida", role: .destructive) { showDiscardLostCapture = true }
                            .disabled(viewModel.isSaving)
                    } else if !document.isProvider {
                        Button("Tentar carregar novamente") { viewModel.load() }
                    }
                }
                if document.isProvider && document.summary.state == .draft && !document.closed {
                    ForEach(GuinchoInspectionPoint.required) { point in
                        pointRow(point, photos: document.requiredPhotos)
                    }
                    ForEach(GuinchoInspectionDetailPoint.allCases) { point in
                        detailPointRow(point, photos: document.namedPhotos)
                    }
                    TextField("Descreva a avaria ou detalhe (opcional)", text: $detailCaption)
                        .textFieldStyle(.roundedBorder)
                    Button("Adicionar outro detalhe") {
                        selectedDetailPoint = nil
                        replacingPhotoID = nil
                        requestCamera(for: .detail)
                    }
                        .frame(minHeight: 48)
                    Button(action: { viewModel.submit() }) {
                        label("Enviar fotos para aprovação")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isSaving || document.summary.requiredPointsReady < 4 || !document.pendingPhotos.isEmpty)
                }
                if document.closed && !viewModel.versions.isEmpty {
                    ForEach(viewModel.versions) { version in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Versão \(version.versionNumber)").font(PitGoTypography.categoryTitle)
                                if version.state == .approved {
                                    Text("Aprovada").font(PitGoTypography.caption).foregroundStyle(.green)
                                }
                            }
                            Text(version.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(PitGoTypography.caption).foregroundStyle(tokens.textSecondary)
                            if let decidedAt = version.decidedAt {
                                Text("Decisão: \(version.state == .approved ? "aprovada" : "correção solicitada") em \(decidedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(PitGoTypography.caption).foregroundStyle(tokens.textSecondary)
                            }
                            if let decidedBy = version.decidedByName, !decidedBy.isEmpty {
                                Text("Decidido por \(decidedBy)").font(PitGoTypography.caption).foregroundStyle(tokens.textSecondary)
                            }
                            if let reason = version.correctionReason, !reason.isEmpty {
                                Text("Correção: \(reason)").font(PitGoTypography.body)
                            }
                            ForEach(viewModel.versionPhotos[version.id] ?? []) { photo in photoRow(photo) }
                        }
                        .padding(14)
                        .background(tokens.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    if viewModel.hasMoreVersions {
                        Button("Carregar versões anteriores") { viewModel.loadMoreVersions() }
                            .disabled(viewModel.isLoadingMoreVersions)
                    }
                    if viewModel.isLoadingMoreVersions { ProgressView().frame(maxWidth: .infinity) }
                } else if !document.isProvider || document.summary.state != .draft {
                    // A página contém todas as fotos selecionadas desta versão, inclusive detalhes.
                    // requiredPhotos e namedPhotos se sobrepõem e servem aos pontos de captura.
                    ForEach(viewModel.photos) { photo in photoRow(photo) }
                }
                if viewModel.hasMorePhotos {
                    Button("Carregar próximas fotos") { viewModel.loadMorePhotos() }
                        .disabled(viewModel.isLoadingMorePhotos)
                }
                if viewModel.isLoadingMorePhotos { ProgressView().frame(maxWidth: .infinity) }
                if !document.isProvider && document.summary.state == .submitted && !document.closed {
                    Button("Aprovar fotos") { viewModel.approve() }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isSaving || !allCurrentPhotosLoaded(document))
                    Button("Solicitar correção") { showCorrection = true }
                        .disabled(viewModel.isSaving || !allCurrentPhotosLoaded(document))
                }
                if document.isProvider && document.summary.state == .correctionRequested && !document.closed {
                    Button("Preparar nova versão") { viewModel.beginCorrection() }
                        .buttonStyle(.borderedProminent).disabled(viewModel.isSaving)
                }
                if viewModel.isSaving { ProgressView().frame(maxWidth: .infinity) }
            }
            .padding(20)
        }
    }

    private func pointRow(_ point: GuinchoInspectionPoint, photos: [GuinchoInspectionPhoto]) -> some View {
        let photo = photos.first { $0.point == point }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(point.title).font(PitGoTypography.categoryTitle)
                    Text(photo == nil ? "Pendente" : "Foto salva")
                        .font(PitGoTypography.caption).foregroundStyle(tokens.textSecondary)
                }
                Spacer()
                Button(photo == nil ? "Fotografar" : "Refazer") {
                    replacingPhotoID = photo?.id
                    requestCamera(for: point)
                }
                .disabled(viewModel.isSaving)
            }
            if let photo { photoRow(photo) }
        }
        .padding(14)
        .background(tokens.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder private func photoRow(_ photo: GuinchoInspectionPhoto) -> some View {
        if let image = viewModel.images[photo.id] {
            Button { selectedPhoto = photo } label: {
                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ampliar foto: \(photo.point.title)")
            Text("\(photo.displayTitle) · \(photo.capturedAt.formatted(date: .abbreviated, time: .shortened)) · \(photo.capturedByName)")
                .font(PitGoTypography.caption).foregroundStyle(tokens.textSecondary)
            if let savedAt = photo.savedAt {
                Text("Salva em \(savedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(PitGoTypography.caption).foregroundStyle(tokens.textSecondary)
            }
        } else {
            HStack { ProgressView(); Text("Carregando foto…").font(PitGoTypography.caption) }
        }
    }

    private func allCurrentPhotosLoaded(_ document: GuinchoInspectionDocument) -> Bool {
        !viewModel.hasMorePhotos && !viewModel.photos.isEmpty && viewModel.photos.allSatisfy { viewModel.images[$0.id] != nil }
    }

    private func statusText(_ summary: GuinchoInspectionSummary) -> String {
        switch summary.state {
        case .draft: "Fotos pendentes — registre os quatro pontos do veículo."
        case .submitted: "Aguardando aprovação das fotos pelo cliente."
        case .correctionRequested: "Correção solicitada."
        case .approved: "Fotos aprovadas pelo cliente."
        case nil: "Vistoria não registrada."
        }
    }

    private func requestCamera(for point: GuinchoInspectionPoint) {
        capturePoint = point
        selectedDetailPoint = nil
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: showCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { showCamera = true } else { cameraMessage = "Permita o acesso à câmera nos Ajustes." }
                }
            }
        default: cameraMessage = "Permita o acesso à câmera nos Ajustes."
        }
    }

    private func detailPointRow(_ point: GuinchoInspectionDetailPoint, photos: [GuinchoInspectionPhoto]) -> some View {
        let photo = photos.first { $0.point == .detail && $0.detailPoint == point.rawValue }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(point.title).font(PitGoTypography.categoryTitle)
                    Text(photo == nil ? "Opcional · não registrado" : "Foto salva")
                        .font(PitGoTypography.caption).foregroundStyle(tokens.textSecondary)
                }
                Spacer()
                Button(photo == nil ? "Fotografar" : "Refazer") {
                    replacingPhotoID = photo?.id
                    requestCamera(for: point)
                }
                .disabled(viewModel.isSaving)
            }
            if let photo { photoRow(photo) }
        }
        .padding(14)
        .background(tokens.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func requestCamera(for detailPoint: GuinchoInspectionDetailPoint) {
        selectedDetailPoint = detailPoint
        capturePoint = .detail
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: showCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { showCamera = true } else { cameraMessage = "Permita o acesso à câmera nos Ajustes." }
                }
            }
        default: cameraMessage = "Permita o acesso à câmera nos Ajustes."
        }
    }

    private func label(_ title: String) -> some View {
        HStack { if viewModel.isSaving { ProgressView() }; Text(title) }
            .frame(maxWidth: .infinity, minHeight: 48)
    }
}
