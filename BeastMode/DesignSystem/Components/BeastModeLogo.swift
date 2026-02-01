import SwiftUI

/// Beast Mode app logo
struct BeastModeLogo: View {
    var size: CGFloat = 80
    var showText: Bool = true

    var body: some View {
        VStack(spacing: size * 0.15) {
            // Icon
            ZStack {
                // Background circle
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.beastPrimary, .beastSecondary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size, height: size)

                // Beast icon (using SF Symbol as placeholder)
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: size * 0.45, weight: .bold))
                    .foregroundStyle(.white)
            }
            .shadow(color: .beastPrimary.opacity(0.4), radius: size * 0.15, x: 0, y: size * 0.05)

            if showText {
                VStack(spacing: 2) {
                    Text("BEAST")
                        .font(.system(size: size * 0.25, weight: .black, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("MODE")
                        .font(.system(size: size * 0.18, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Compact logo for navigation bars and small spaces
struct BeastModeLogoCompact: View {
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.2)
                .fill(
                    LinearGradient(
                        colors: [.beastPrimary, .beastSecondary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)

            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

/// App icon style logo
struct BeastModeAppIcon: View {
    var size: CGFloat = 120

    var body: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: size * 0.22)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.4, green: 0.33, blue: 0.56),
                            Color(red: 0.55, green: 0.35, blue: 0.65)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Inner glow
            RoundedRectangle(cornerRadius: size * 0.18)
                .fill(
                    RadialGradient(
                        colors: [.white.opacity(0.2), .clear],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: size * 0.8
                    )
                )
                .padding(size * 0.05)

            // Icon
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
        }
        .frame(width: size, height: size)
    }
}

/// Loading indicator with beast logo
struct BeastModeLoader: View {
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.beastPrimary.opacity(0.3), lineWidth: 3)
                .frame(width: 50, height: 50)

            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(Color.beastPrimary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 50, height: 50)
                .rotationEffect(.degrees(isAnimating ? 360 : 0))

            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.beastPrimary)
        }
        .onAppear {
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                isAnimating = true
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 40) {
        BeastModeLogo(size: 100)

        BeastModeLogo(size: 60, showText: false)

        HStack(spacing: 20) {
            BeastModeLogoCompact(size: 40)
            BeastModeLogoCompact(size: 32)
            BeastModeLogoCompact(size: 24)
        }

        BeastModeAppIcon(size: 120)

        BeastModeLoader()
    }
    .padding()
}
