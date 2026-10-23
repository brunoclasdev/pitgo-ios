import Foundation
import Supabase

struct StoreSummary: Decodable, Identifiable {
    let id: UUID
    let name: String
    let description: String?
    let city: String
}

struct StoreProduct: Decodable, Identifiable {
    let id: UUID
    let storeProviderID: UUID
    let name: String
    let description: String
    let price: Decimal
    let imagePath: String?
    let active: Bool
    var imageURL: URL?

    enum CodingKeys: String, CodingKey {
        case id, name, description, price, active
        case storeProviderID = "store_provider_id"
        case imagePath = "image_path"
    }
}

struct StoreProductDraft: Identifiable {
    var id = UUID()
    var name = ""
    var description = ""
    var price = ""
    var active = true
    var imagePath: String?
    var photoData: Data?
    var photoType = "image/jpeg"
}

private struct StoreProductListParams: Encodable { let p_store_id: UUID }
private struct StoreProductDeleteParams: Encodable { let p_product_id: UUID }
private struct StoreProductWrite: Encodable {
    let id: UUID
    let name: String
    let description: String
    let price: String
    let image_path: String?
    let active: Bool
}
private struct StoreProductSaveParams: Encodable { let p_product: StoreProductWrite }

final class StoreRepository {
    private let client: SupabaseClient
    private let bucket = "store-product-images"

    init(client: SupabaseClient) { self.client = client }

    func stores() async throws -> [StoreSummary] {
        try await client.rpc("list_stores").execute().value
    }

    func products(storeID: UUID) async throws -> [StoreProduct] {
        let rows: [StoreProduct] = try await client.rpc(
            "list_store_products", params: StoreProductListParams(p_store_id: storeID)
        ).execute().value
        var results: [StoreProduct] = []
        for var row in rows {
            if let path = row.imagePath {
                row.imageURL = try? await client.storage.from(bucket).createSignedURL(path: path, expiresIn: 300)
            }
            results.append(row)
        }
        return results
    }

    func upload(photo: Data, mime: String, storeID: UUID, productID: UUID) async throws -> String {
        guard photo.count <= 5 * 1024 * 1024, ["image/jpeg", "image/png", "image/webp"].contains(mime) else {
            throw StoreFailure.invalidPhoto
        }
        let ext = mime == "image/png" ? "png" : (mime == "image/webp" ? "webp" : "jpg")
        let path = "\(storeID.uuidString.lowercased())/\(productID.uuidString.lowercased())/\(UUID().uuidString.lowercased()).\(ext)"
        try await client.storage.from(bucket).upload(path, data: photo, options: FileOptions(contentType: mime, upsert: false))
        return path
    }

    func save(_ draft: StoreProductDraft) async throws {
        let price = draft.price.replacingOccurrences(of: ",", with: ".")
        try await client.rpc("save_store_product", params: StoreProductSaveParams(p_product: StoreProductWrite(
            id: draft.id, name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            description: draft.description.trimmingCharacters(in: .whitespacesAndNewlines),
            price: price, image_path: draft.imagePath, active: draft.active
        ))).execute()
    }

    func delete(_ product: StoreProduct) async throws {
        try await client.rpc("delete_store_product", params: StoreProductDeleteParams(p_product_id: product.id)).execute()
        if let path = product.imagePath { try? await client.storage.from(bucket).remove(paths: [path]) }
    }
}

enum StoreFailure: Error { case invalidPhoto }
