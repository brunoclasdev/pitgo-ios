import SwiftUI

/// A bounded overlay: the map keeps the full viewport and remains interactive outside the card.
struct ServiceMapCard<Content: View>: View {
    @Environment(\.pitGoTokens) private var tokens
    @State private var contentHeight: CGFloat = 180
    var placement: VerticalEdge = .bottom
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { geometry in
            VStack {
                if placement == .bottom { Spacer(minLength: 0) }
                ScrollView {
                    content()
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .background {
                            GeometryReader { card in
                                Color.clear
                                    .onAppear { contentHeight = max(44, card.size.height) }
                                    .onChange(of: card.size.height) { contentHeight = max(44, $0) }
                            }
                        }
                }
                .frame(height: min(contentHeight, geometry.size.height * 0.48))
                .background(tokens.surface, in: RoundedRectangle(cornerRadius: 20))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay {
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(tokens.accent, lineWidth: 1.5)
                        .allowsHitTesting(false)
                }
                .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
                .padding(12)
                if placement == .top { Spacer(minLength: 0) }
            }
        }
    }
}
