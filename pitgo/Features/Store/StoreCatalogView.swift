import PhotosUI
import SwiftUI
import UIKit

struct StoreCatalogView: View {
    @Environment(\.pitGoTokens) private var tokens
    let repository: StoreRepository
    let ownerStoreID: UUID?
    @State private var stores: [StoreSummary] = []
    @State private var products: [StoreProduct] = []
    @State private var selectedStore: StoreSummary?
    @State private var isLoading = false
    @State private var failure: String?
    @State private var draft: StoreProductDraft?

    var body: some View {
        Group {
            if let storeID = ownerStoreID {
                productList(storeID: storeID, owner: true)
            } else if let selectedStore {
                productList(storeID: selectedStore.id, owner: false)
            } else {
                storeList
            }
        }
        .background(tokens.background)
        .navigationTitle(ownerStoreID == nil && selectedStore == nil ? "Lojas" : (selectedStore?.name ?? "Produtos"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if ownerStoreID == nil, selectedStore != nil {
                ToolbarItem(placement: .navigationBarLeading) { Button("Lojas") { selectedStore = nil; products = [] } }
            }
        }
        .task { await load() }
        .sheet(item: $draft) { value in
            NavigationStack {
                StoreProductEditor(draft: value, onSave: { updated in
                    await save(updated)
                }, onCancel: { draft = nil })
            }
        }
    }

    private var storeList: some View {
        List {
            if let failure { Text(failure).foregroundStyle(.red) }
            if isLoading { ProgressView().frame(maxWidth: .infinity) }
            ForEach(stores) { store in
                Button { selectedStore = store } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.name).font(.headline).foregroundStyle(tokens.textPrimary)
                        if let description = store.description { Text(description).foregroundStyle(tokens.textSecondary) }
                        Text(store.city).font(.caption).foregroundStyle(tokens.textSecondary)
                    }.padding(.vertical, 5)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func productList(storeID: UUID, owner: Bool) -> some View {
        List {
            if owner {
                Button { draft = StoreProductDraft() } label: { Label("Adicionar produto", systemImage: "plus") }
                    .disabled(isLoading)
            }
            if let failure { Text(failure).foregroundStyle(.red) }
            if isLoading { ProgressView().frame(maxWidth: .infinity) }
            ForEach(products) { product in
                StoreProductRow(product: product, owner: owner) {
                    draft = StoreProductDraft(id: product.id, name: product.name, description: product.description,
                                              price: NSDecimalNumber(decimal: product.price).stringValue,
                                              active: product.active, imagePath: product.imagePath)
                } onDelete: {
                    Task { await delete(product, storeID: storeID) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .task(id: storeID) { if products.isEmpty { await loadProducts(storeID) } }
    }

    @MainActor private func load() async {
        guard ownerStoreID == nil else { return }
        isLoading = true
        defer { isLoading = false }
        do { stores = try await repository.stores() }
        catch { failure = "Não foi possível carregar as lojas. Tente novamente." }
    }

    @MainActor private func loadProducts(_ id: UUID) async {
        isLoading = true
        defer { isLoading = false }
        do { products = try await repository.products(storeID: id); failure = nil }
        catch { failure = "Não foi possível carregar os produtos. Tente novamente." }
    }

    @MainActor private func save(_ updated: StoreProductDraft) async -> String? {
        guard let ownerStoreID else { return "Não foi possível identificar a loja." }
        let amountText = updated.price.replacingOccurrences(of: ",", with: ".")
        guard !updated.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, updated.name.count <= 150,
              !updated.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, updated.description.count <= 2000,
              let amount = Decimal(string: amountText), amount > 0 else {
            return "Preencha nome, descrição e um preço válido maior que zero."
        }
        isLoading = true
        defer { isLoading = false }
        do {
            var value = updated
            if let photo = updated.photoData {
                value.imagePath = try await repository.upload(photo: photo, mime: updated.photoType, storeID: ownerStoreID, productID: updated.id)
            }
            try await repository.save(value)
            draft = nil
            await loadProducts(ownerStoreID)
            return nil
        } catch {
            return "Não foi possível salvar o produto. Seus dados continuam disponíveis para tentar novamente."
        }
    }

    @MainActor private func delete(_ product: StoreProduct, storeID: UUID) async {
        do { try await repository.delete(product); await loadProducts(storeID) }
        catch { failure = "Não foi possível remover o produto." }
    }
}

private struct StoreProductRow: View {
    let product: StoreProduct
    let owner: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let url = product.imageURL { AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Color.gray.opacity(0.15) }.frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: 8)) }
            VStack(alignment: .leading, spacing: 4) {
                Text(product.name).font(.headline)
                Text(product.description).font(.subheadline)
                Text(product.price, format: .currency(code: "BRL")).font(.subheadline.weight(.semibold))
                if owner && !product.active { Text("Inativo").font(.caption).foregroundStyle(.secondary) }
                if owner {
                    HStack {
                        Button("Editar", action: onEdit)
                        Button("Remover", role: .destructive, action: onDelete)
                    }
                }
            }
        }.padding(.vertical, 5)
    }
}

private struct StoreProductEditor: View {
    @State var draft: StoreProductDraft
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isSaving = false
    @State private var photoError: String?
    let onSave: (StoreProductDraft) async -> String?
    let onCancel: () -> Void

    var body: some View {
        Form {
            TextField("Nome do produto", text: $draft.name)
            TextField("Descrição", text: $draft.description, axis: .vertical).lineLimit(3...6)
            TextField("Preço (R$)", text: $draft.price).keyboardType(.decimalPad)
            Toggle("Ativo no catálogo", isOn: $draft.active)
            PhotosPicker(selection: $selectedPhoto, matching: .images) { Label("Adicionar foto (opcional)", systemImage: "photo") }
            if draft.photoData != nil { Text("Foto selecionada") }
            if let photoError { Text(photoError).font(.caption).foregroundStyle(.red) }
        }
        .navigationTitle("Produto")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar", action: onCancel).disabled(isSaving) }
            ToolbarItem(placement: .confirmationAction) { Button("Salvar") { Task { isSaving = true; photoError = await onSave(draft); isSaving = false; if photoError == nil { onCancel() } } }.disabled(isSaving) }
        }
        .onChange(of: selectedPhoto) { item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.82),
                      jpeg.count <= 5 * 1024 * 1024 else {
                    photoError = "Não foi possível usar esta foto. Escolha outra imagem de até 5 MB."
                    return
                }
                draft.photoData = jpeg
                draft.photoType = "image/jpeg"
                photoError = nil
            }
        }
    }
}
