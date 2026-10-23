import SwiftUI

struct ProviderKindSelectionView: View {
    let onSelect: (ProviderKind) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Como sua empresa vai atuar?")
                .font(.title2.weight(.semibold))
            Text("Escolha a modalidade para abrir o cadastro adequado.")
                .font(PitGoTypography.body)
                .foregroundStyle(.secondary)
            ForEach(ProviderKind.allCases, id: \.self) { kind in
                Button { onSelect(kind) } label: {
                    HStack {
                        Text(kind.title).font(.headline)
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .navigationTitle("Cadastro da empresa")
        .navigationBarTitleDisplayMode(.inline)
    }
}
