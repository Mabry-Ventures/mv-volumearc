import SwiftUI

/// A reusable glass-style card container with the iOS 26 Liquid Glass aesthetic
struct GlassCard<Content: View>: View {
    let content: Content
    var cornerRadius: CGFloat
    var padding: CGFloat

    init(
        cornerRadius: CGFloat = 24,
        padding: CGFloat = 16,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .glassBackground(cornerRadius: cornerRadius)
    }
}

/// Glass background modifier for the Liquid Glass design system
struct GlassBackgroundModifier: ViewModifier {
    var cornerRadius: CGFloat
    var opacity: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
                    .opacity(opacity)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.3),
                                .white.opacity(0.1),
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            }
            .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
    }
}

extension View {
    /// Apply a glass background with the Liquid Glass aesthetic
    func glassBackground(cornerRadius: CGFloat = 20, opacity: CGFloat = 0.8) -> some View {
        modifier(GlassBackgroundModifier(cornerRadius: cornerRadius, opacity: opacity))
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        LinearGradient(
            colors: [.beastPrimary, .beastSecondary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        VStack(spacing: 20) {
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Push Day")
                        .font(.headline)
                    Text("6 exercises")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal)

            GlassCard(cornerRadius: 16, padding: 12) {
                HStack {
                    Image(systemName: "dumbbell.fill")
                    Text("Bench Press")
                    Spacer()
                    Text("4 x 8")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
        }
    }
}
