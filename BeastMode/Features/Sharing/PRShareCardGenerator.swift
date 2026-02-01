// PRShareCardGenerator.swift
// BeastMode
// Generates shareable image cards for personal records

import SwiftUI

/// The visual card that gets shared to social media
struct PRShareCard: View {
    let exerciseName: String
    let weight: Double
    let reps: Int
    let prType: PRType
    let date: Date
    let streakDays: Int?

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(hex: "1a1a2e"),
                    Color(hex: "16213e"),
                    Color(hex: "0f3460")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Subtle pattern overlay
            DiagonalLinesPattern()
                .stroke(Color.white.opacity(0.03), lineWidth: 1)

            // Content
            VStack(spacing: 20) {
                // Header with logo
                HStack {
                    BeastModeLogo(size: .small)
                    Spacer()
                    Text(date.formatted(.dateTime.month().day().year()))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }

                Spacer()

                // PR Badge
                VStack(spacing: 8) {
                    // Trophy icon
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.yellow, .orange],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .padding(.bottom, 4)

                    Text(prType.title)
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.yellow, .orange],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )

                    Text(exerciseName.uppercased())
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .tracking(2)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }

                // The Numbers
                HStack(spacing: 32) {
                    VStack(spacing: 4) {
                        Text("\(Int(weight))")
                            .font(.system(size: 56, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Text("LBS")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.6))
                            .tracking(1)
                    }

                    Text("×")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(.white.opacity(0.4))

                    VStack(spacing: 4) {
                        Text("\(reps)")
                            .font(.system(size: 56, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Text("REPS")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.6))
                            .tracking(1)
                    }
                }

                // E1RM display
                if case .estimatedMax = prType {
                    let e1rm = calculateE1RM(weight: weight, reps: reps)
                    Text("Est. 1RM: \(Int(e1rm)) lbs")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))
                }

                // Streak badge (if applicable)
                if let streak = streakDays, streak > 1 {
                    HStack(spacing: 6) {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(.orange)
                        Text("\(streak) day streak")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(.white.opacity(0.1))
                    )
                }

                Spacer()

                // Footer
                HStack {
                    Text("beastmode.app")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.4))

                    Spacer()

                    // QR code placeholder or app icon
                    Image(systemName: "dumbbell.fill")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding(24)
        }
        .frame(width: 390, height: 520)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private func calculateE1RM(weight: Double, reps: Int) -> Double {
        guard reps > 0 else { return weight }
        if reps == 1 { return weight }
        let effectiveReps = min(reps, 12)
        return weight * (36.0 / (37.0 - Double(effectiveReps)))
    }
}

// MARK: - Diagonal Lines Pattern

struct DiagonalLinesPattern: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let spacing: CGFloat = 20

        for i in stride(from: 0, to: rect.width + rect.height, by: spacing) {
            path.move(to: CGPoint(x: i, y: 0))
            path.addLine(to: CGPoint(x: 0, y: i))
        }

        return path
    }
}

// MARK: - Beast Mode Logo

struct BeastModeLogo: View {
    enum Size {
        case small, medium, large

        var fontSize: CGFloat {
            switch self {
            case .small: return 14
            case .medium: return 20
            case .large: return 28
            }
        }

        var iconSize: CGFloat {
            switch self {
            case .small: return 16
            case .medium: return 24
            case .large: return 32
            }
        }
    }

    let size: Size

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "dumbbell.fill")
                .font(.system(size: size.iconSize, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.orange, .red],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("BEAST MODE")
                .font(.system(size: size.fontSize, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Share Card Renderer

/// Renders the share card to a UIImage for sharing
@MainActor
class ShareCardRenderer {
    static func render(card: PRShareCard) -> UIImage? {
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3.0  // High resolution for crisp sharing
        return renderer.uiImage
    }

    static func render(
        exerciseName: String,
        weight: Double,
        reps: Int,
        prType: PRType,
        date: Date = .now,
        streakDays: Int? = nil
    ) -> UIImage? {
        let card = PRShareCard(
            exerciseName: exerciseName,
            weight: weight,
            reps: reps,
            prType: prType,
            date: date,
            streakDays: streakDays
        )
        return render(card: card)
    }
}

// MARK: - Share Sheet

/// Sheet for previewing and sharing the PR card
struct PRShareSheet: View {
    let exerciseName: String
    let weight: Double
    let reps: Int
    let prType: PRType
    let streakDays: Int?

    @Environment(\.dismiss) private var dismiss
    @State private var shareImage: UIImage?
    @State private var isSharePresented = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Preview
                PRShareCard(
                    exerciseName: exerciseName,
                    weight: weight,
                    reps: reps,
                    prType: prType,
                    date: .now,
                    streakDays: streakDays
                )
                .scaleEffect(0.75)
                .frame(height: 390)

                // Share button
                Button {
                    generateAndShare()
                } label: {
                    Label("Share to...", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(hex: "FF6B35"))
                        )
                        .foregroundStyle(.white)
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top)
            .navigationTitle("Share Your PR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $isSharePresented) {
            if let image = shareImage {
                ActivityViewControllerWrapper(
                    items: [
                        image,
                        "Just hit a new PR on \(exerciseName)! 💪🔥 #BeastMode"
                    ]
                )
            }
        }
    }

    private func generateAndShare() {
        shareImage = ShareCardRenderer.render(
            exerciseName: exerciseName,
            weight: weight,
            reps: reps,
            prType: prType,
            streakDays: streakDays
        )
        isSharePresented = true
    }
}

// MARK: - Activity View Controller Wrapper

#if os(iOS)
struct ActivityViewControllerWrapper: UIViewControllerRepresentable {
    let items: [Any]
    var activities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: items,
            applicationActivities: activities
        )
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#else
struct ActivityViewControllerWrapper: View {
    let items: [Any]

    var body: some View {
        Text("Sharing not available on this platform")
    }
}
#endif

// MARK: - Preview

#Preview("Share Card") {
    PRShareCard(
        exerciseName: "Barbell Bench Press",
        weight: 225,
        reps: 5,
        prType: .estimatedMax(improvement: 15),
        date: .now,
        streakDays: 14
    )
}

#Preview("Share Sheet") {
    PRShareSheet(
        exerciseName: "Barbell Bench Press",
        weight: 225,
        reps: 5,
        prType: .heaviestWeight(weight: 225),
        streakDays: 7
    )
}
