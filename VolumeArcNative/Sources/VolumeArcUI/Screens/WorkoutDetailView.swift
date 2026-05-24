#if canImport(SwiftUI)
import SwiftUI
import VolumeArcCore
#if canImport(ImagePlayground) && os(iOS)
import ImagePlayground
#endif

/// Detail view pushed from TodayView's next workout card.
/// Uses `.navigationTransition(.zoom(...))` to hero-animate from the card.
struct WorkoutDetailView: View {
    let title: String
    let exerciseID: String
    let exerciseName: String
    let target: String
    let cue: String
    let reason: String
    let heroNamespace: Namespace.ID
    @State private var isShowingImagePlayground = false
    @State private var savedCueIllustrationURL: URL?
    @State private var cueIllustrationSaveError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VA.Space.lg) {
                header
                targetCard
                cueCard
                cueIllustrationCard
                reasonCard
                Spacer(minLength: VA.Space.xxl)
            }
            .padding(VA.Space.lg)
        }
        .background(VA.Colors.surfaceGrouped)
        // VOL-200 P3: stable identifier so the `today.next-workout-tap`
        // journey test can assert this view appeared after tapping the
        // next workout card.
        .accessibilityIdentifier("workout.detail.root")
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .cueImagePlaygroundSheet(
            isPresented: $isShowingImagePlayground,
            concepts: imagePlaygroundConcepts,
            sourceImage: sourceExerciseImage,
            onCompletion: saveGeneratedCueIllustration
        )
        .onAppear {
            savedCueIllustrationURL = try? ExerciseCueIllustrationStore()
                .latestIllustrationURL(for: exerciseID)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: VA.Space.xs) {
            Text(String(localized: "FOCUS", comment: "Workout detail header label for the main lift"))
                .font(VA.Typography.caption)
                .foregroundStyle(VA.Colors.textSecondary)
                .tracking(0.5)
            Text(exerciseName)
                .font(VA.Typography.display)
                .foregroundStyle(VA.Colors.textPrimary)
        }
    }

    private var targetCard: some View {
        VACard(style: .accent) {
            VStack(alignment: .leading, spacing: VA.Space.sm) {
                Text(String(localized: "TARGET", comment: "Workout detail target card label"))
                    .font(VA.Typography.caption)
                    .foregroundStyle(VA.Colors.primary)
                    .tracking(0.5)
                Text(target)
                    .font(VA.Typography.title2)
                    .foregroundStyle(VA.Colors.textPrimary)
                    .monospacedDigit()
            }
        }
    }

    private var cueCard: some View {
        VACard(style: .glass) {
            VStack(alignment: .leading, spacing: VA.Space.sm) {
                HStack(spacing: VA.Space.xs) {
                    Image(systemName: "quote.opening")
                        .foregroundStyle(VA.Colors.primary)
                    Text(String(localized: "CUE", comment: "Workout detail coach cue card label"))
                        .font(VA.Typography.caption)
                        .foregroundStyle(VA.Colors.textSecondary)
                        .tracking(0.5)
                }
                Text(cue)
                    .font(VA.Typography.body)
                    .foregroundStyle(VA.Colors.textPrimary)
                    .italic()
            }
        }
    }

    @ViewBuilder
    private var cueIllustrationCard: some View {
        #if canImport(ImagePlayground) && os(iOS)
        if supportsImagePlayground {
            VACard(style: .flat) {
                VStack(alignment: .leading, spacing: VA.Space.md) {
                    HStack(spacing: VA.Space.sm) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(VA.Colors.primary)
                        VStack(alignment: .leading, spacing: VA.Space.xxs) {
                            Text(String(localized: "Form cue image", comment: "Workout detail image generation title"))
                                .font(VA.Typography.headline)
                                .foregroundStyle(VA.Colors.textPrimary)
                            if savedCueIllustrationURL != nil {
                                Text(String(localized: "Saved locally", comment: "Workout detail saved generated cue image status"))
                                    .font(VA.Typography.footnote)
                                    .foregroundStyle(VA.Colors.textSecondary)
                            }
                        }
                        Spacer()
                    }

                    if let savedCueIllustrationURL {
                        LocalCueIllustrationPreview(url: savedCueIllustrationURL)
                    }

                    if let cueIllustrationSaveError {
                        Text(cueIllustrationSaveError)
                            .font(VA.Typography.footnote)
                            .foregroundStyle(VA.Colors.error)
                    }

                    VAButton(
                        String(localized: "Generate my form cue", comment: "Workout detail Image Playground button"),
                        icon: "wand.and.sparkles",
                        style: .secondary,
                        accessibilityIdentifier: "workout.detail.generateCueImage"
                    ) {
                        isShowingImagePlayground = true
                    }
                }
            }
        }
        #endif
    }

    private var reasonCard: some View {
        VACard(style: .flat) {
            VStack(alignment: .leading, spacing: VA.Space.sm) {
                Text(String(localized: "WHY THIS PROGRESSION", comment: "Workout detail reasoning card label"))
                    .font(VA.Typography.caption)
                    .foregroundStyle(VA.Colors.textSecondary)
                    .tracking(0.5)
                Text(reason)
                    .font(VA.Typography.body)
                    .foregroundStyle(VA.Colors.textPrimary)
            }
        }
    }

    private var imagePlaygroundConcepts: [String] {
        [
            String(
                localized: "\(exerciseName) strength-training form cue, instructional illustration, no text labels.",
                comment: "Image Playground concept for exercise cue generation"
            ),
            String(
                localized: "Emphasize this cue: \(cue)",
                comment: "Image Playground concept for exercise cue generation"
            ),
        ]
    }

    private var sourceExerciseImage: Image? {
        guard let exercise = VolumeArcExerciseCatalog.exercise(withID: exerciseID) else {
            return nil
        }
        return Image(exercise.illustrationAssetName, bundle: .main)
    }

    #if canImport(ImagePlayground) && os(iOS)
    private var supportsImagePlayground: Bool {
        if #available(iOS 18.1, *) {
            ImagePlaygroundViewController.isAvailable
        } else {
            false
        }
    }
    #endif

    private func saveGeneratedCueIllustration(from sourceURL: URL) {
        do {
            let savedURL = try ExerciseCueIllustrationStore()
                .saveGeneratedImage(from: sourceURL, exerciseID: exerciseID)
            savedCueIllustrationURL = savedURL
            cueIllustrationSaveError = nil
        } catch {
            cueIllustrationSaveError = String(
                localized: "Image was not saved.",
                comment: "Workout detail generated cue image save failure"
            )
        }
    }
}

#if canImport(ImagePlayground) && os(iOS)
private struct LocalCueIllustrationPreview: View {
    let url: URL

    var body: some View {
        if let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 180)
                .clipShape(RoundedRectangle(cornerRadius: VA.Radius.md))
                .accessibilityLabel(String(
                    localized: "Generated form cue image",
                    comment: "Accessibility label for generated exercise cue illustration"
                ))
        }
    }
}
#endif

private extension View {
    @ViewBuilder
    func cueImagePlaygroundSheet(
        isPresented: Binding<Bool>,
        concepts: [String],
        sourceImage: Image?,
        onCompletion: @escaping (URL) -> Void
    ) -> some View {
        #if canImport(ImagePlayground) && os(iOS)
        if #available(iOS 18.1, *) {
            self.imagePlaygroundSheet(
                isPresented: isPresented,
                concepts: concepts.map(ImagePlaygroundConcept.text),
                sourceImage: sourceImage,
                onCompletion: onCompletion
            )
        } else {
            self
        }
        #else
        self
        #endif
    }
}
#endif
