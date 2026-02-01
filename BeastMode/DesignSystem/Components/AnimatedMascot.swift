import SwiftUI

/// Animated Beast mascot character
struct AnimatedBeastMascot: View {
    @State private var isAnimating = false
    var mood: MascotMood = .idle
    var size: CGFloat = 80

    enum MascotMood {
        case idle
        case cheering
        case thinking
        case celebrating
        case struggling
    }

    var body: some View {
        ZStack {
            // Base bear shape
            BearShape()
                .fill(
                    LinearGradient(
                        colors: [.beastPrimary, .beastPrimary.opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size, height: size)
                .scaleEffect(isAnimating ? animationScale : 1.0)
                .rotationEffect(.degrees(animationRotation))

            // Face
            VStack(spacing: size * 0.05) {
                // Eyes
                HStack(spacing: size * 0.2) {
                    EyeView(mood: mood, size: size * 0.12)
                    EyeView(mood: mood, size: size * 0.12)
                }

                // Mouth
                MouthView(mood: mood, size: size * 0.2)
            }
            .offset(y: size * 0.05)

            // Additional elements based on mood
            moodOverlay
        }
        .onAppear {
            startAnimation()
        }
        .onChange(of: mood) { _, _ in
            startAnimation()
        }
    }

    private var animationScale: CGFloat {
        switch mood {
        case .idle: return 1.03
        case .cheering: return 1.1
        case .thinking: return 1.0
        case .celebrating: return 1.15
        case .struggling: return 0.98
        }
    }

    private var animationRotation: Double {
        switch mood {
        case .cheering: return isAnimating ? 3 : -3
        case .celebrating: return isAnimating ? 5 : -5
        default: return 0
        }
    }

    @ViewBuilder
    private var moodOverlay: some View {
        switch mood {
        case .celebrating:
            // Confetti effect
            ForEach(0..<5) { index in
                Circle()
                    .fill([Color.yellow, .orange, .green, .blue, .pink][index])
                    .frame(width: size * 0.08, height: size * 0.08)
                    .offset(
                        x: CGFloat.random(in: -size * 0.6...size * 0.6),
                        y: isAnimating ? -size * 0.8 : size * 0.3
                    )
                    .opacity(isAnimating ? 0 : 1)
            }
        case .thinking:
            // Thought bubble
            Circle()
                .fill(.white.opacity(0.8))
                .frame(width: size * 0.15, height: size * 0.15)
                .offset(x: size * 0.4, y: -size * 0.3)
                .opacity(isAnimating ? 0.8 : 0.4)
        default:
            EmptyView()
        }
    }

    private func startAnimation() {
        let duration: Double
        let autoreverses: Bool

        switch mood {
        case .idle:
            duration = 2.0
            autoreverses = true
        case .cheering, .celebrating:
            duration = 0.3
            autoreverses = true
        case .thinking:
            duration = 1.5
            autoreverses = true
        case .struggling:
            duration = 0.5
            autoreverses = true
        }

        withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: autoreverses)) {
            isAnimating = true
        }
    }
}

/// Bear head shape
struct BearShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        let headRadius = min(rect.width, rect.height) * 0.4
        let centerX = rect.midX
        let centerY = rect.midY

        // Main head circle
        path.addEllipse(in: CGRect(
            x: centerX - headRadius,
            y: centerY - headRadius * 0.8,
            width: headRadius * 2,
            height: headRadius * 2
        ))

        // Left ear
        let earSize = headRadius * 0.45
        path.addEllipse(in: CGRect(
            x: centerX - headRadius * 0.85,
            y: centerY - headRadius * 1.1,
            width: earSize,
            height: earSize
        ))

        // Right ear
        path.addEllipse(in: CGRect(
            x: centerX + headRadius * 0.4,
            y: centerY - headRadius * 1.1,
            width: earSize,
            height: earSize
        ))

        return path
    }
}

/// Eye component
struct EyeView: View {
    let mood: AnimatedBeastMascot.MascotMood
    let size: CGFloat

    var body: some View {
        ZStack {
            // Eye white
            Ellipse()
                .fill(.white)
                .frame(width: size, height: size * eyeHeight)

            // Pupil
            Circle()
                .fill(.black)
                .frame(width: size * 0.5, height: size * 0.5)
                .offset(y: pupilOffset)
        }
    }

    private var eyeHeight: CGFloat {
        switch mood {
        case .celebrating: return 0.6
        case .struggling: return 1.2
        default: return 0.9
        }
    }

    private var pupilOffset: CGFloat {
        switch mood {
        case .thinking: return -size * 0.1
        default: return 0
        }
    }
}

/// Mouth component
struct MouthView: View {
    let mood: AnimatedBeastMascot.MascotMood
    let size: CGFloat

    var body: some View {
        switch mood {
        case .idle:
            // Slight smile
            Capsule()
                .fill(.white)
                .frame(width: size, height: size * 0.4)

        case .cheering, .celebrating:
            // Big smile
            ZStack {
                Capsule()
                    .fill(.white)
                    .frame(width: size * 1.3, height: size * 0.6)

                // Teeth hint
                Rectangle()
                    .fill(.white.opacity(0.3))
                    .frame(width: size, height: size * 0.15)
                    .offset(y: -size * 0.15)
            }

        case .thinking:
            // Small O
            Circle()
                .fill(.white)
                .frame(width: size * 0.4, height: size * 0.4)

        case .struggling:
            // Grimace
            Capsule()
                .fill(.white)
                .frame(width: size * 0.8, height: size * 0.25)
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 30) {
        HStack(spacing: 30) {
            VStack {
                AnimatedBeastMascot(mood: .idle)
                Text("Idle").font(.caption)
            }
            VStack {
                AnimatedBeastMascot(mood: .cheering)
                Text("Cheering").font(.caption)
            }
        }

        HStack(spacing: 30) {
            VStack {
                AnimatedBeastMascot(mood: .thinking)
                Text("Thinking").font(.caption)
            }
            VStack {
                AnimatedBeastMascot(mood: .celebrating)
                Text("Celebrating").font(.caption)
            }
        }

        VStack {
            AnimatedBeastMascot(mood: .struggling)
            Text("Struggling").font(.caption)
        }
    }
    .padding()
}
