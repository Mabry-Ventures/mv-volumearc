import SwiftUI

/// A glass-style button with the Liquid Glass aesthetic
struct GlassButton: View {
    let title: String
    let icon: String?
    let action: () -> Void

    @State private var isPressed = false

    init(_ title: String, icon: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                }
                Text(title)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .glassBackground(cornerRadius: .infinity)
        }
        .buttonStyle(GlassButtonStyle())
    }
}

/// A larger, more prominent glass button
struct GlassButtonLarge: View {
    let title: String
    let icon: String?
    let action: () -> Void

    init(_ title: String, icon: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let icon {
                    Image(systemName: icon)
                        .font(.title2)
                }
                Text(title)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .glassBackground(cornerRadius: 16)
        }
        .buttonStyle(GlassButtonStyle())
    }
}

/// Button style for glass buttons
struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

/// An icon-only glass button
struct GlassIconButton: View {
    let icon: String
    let action: () -> Void
    var size: CGFloat = 44

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.4, weight: .medium))
                .frame(width: size, height: size)
                .glassBackground(cornerRadius: size / 2)
        }
        .buttonStyle(GlassButtonStyle())
    }
}

/// A tinted glass button with a background color
struct TintedGlassButton: View {
    let title: String
    let icon: String?
    let tint: Color
    let action: () -> Void

    init(_ title: String, icon: String? = nil, tint: Color = .beastPrimary, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                }
                Text(title)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background {
                Capsule()
                    .fill(tint.gradient)
            }
            .shadow(color: tint.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(GlassButtonStyle())
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        LinearGradient(
            colors: [.beastPrimary.opacity(0.3), .beastSecondary.opacity(0.3)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        VStack(spacing: 24) {
            GlassButton("Start Workout", icon: "play.fill") {
                print("Tapped")
            }

            GlassButtonLarge("Begin Session", icon: "figure.strengthtraining.traditional") {
                print("Tapped")
            }
            .padding(.horizontal)

            HStack(spacing: 16) {
                GlassIconButton(icon: "minus") {}
                GlassIconButton(icon: "play.fill") {}
                GlassIconButton(icon: "plus") {}
            }

            TintedGlassButton("Save", icon: "checkmark", tint: .green) {
                print("Tapped")
            }
        }
    }
}
