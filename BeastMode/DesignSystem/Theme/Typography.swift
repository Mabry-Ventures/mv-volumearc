import SwiftUI

// MARK: - Beast Mode Typography

extension Font {
    // MARK: - Display Fonts

    /// Large title - 34pt bold rounded
    static let beastLargeTitle = Font.system(size: 34, weight: .bold, design: .rounded)

    /// Title - 28pt semibold rounded
    static let beastTitle = Font.system(size: 28, weight: .semibold, design: .rounded)

    /// Title 2 - 22pt semibold rounded
    static let beastTitle2 = Font.system(size: 22, weight: .semibold, design: .rounded)

    /// Title 3 - 20pt semibold rounded
    static let beastTitle3 = Font.system(size: 20, weight: .semibold, design: .rounded)

    // MARK: - Body Fonts

    /// Headline - 17pt semibold
    static let beastHeadline = Font.system(size: 17, weight: .semibold)

    /// Body - 17pt regular
    static let beastBody = Font.system(size: 17, weight: .regular)

    /// Callout - 16pt regular
    static let beastCallout = Font.system(size: 16, weight: .regular)

    /// Subheadline - 15pt regular
    static let beastSubheadline = Font.system(size: 15, weight: .regular)

    // MARK: - Supporting Fonts

    /// Footnote - 13pt regular
    static let beastFootnote = Font.system(size: 13, weight: .regular)

    /// Caption - 12pt regular
    static let beastCaption = Font.system(size: 12, weight: .regular)

    /// Caption 2 - 11pt regular
    static let beastCaption2 = Font.system(size: 11, weight: .regular)

    // MARK: - Number Fonts

    /// Number font - for weights, reps, timers
    static func beastNumber(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        Font.system(size: size, weight: weight, design: .rounded)
    }

    /// Large number - 48pt for prominent stats
    static let beastLargeNumber = Font.system(size: 48, weight: .bold, design: .rounded)

    /// Medium number - 32pt for set info
    static let beastMediumNumber = Font.system(size: 32, weight: .semibold, design: .rounded)

    /// Small number - 24pt for secondary stats
    static let beastSmallNumber = Font.system(size: 24, weight: .medium, design: .rounded)

    // MARK: - Monospaced (for timers)

    /// Timer font - monospaced for countdowns
    static func beastTimer(_ size: CGFloat) -> Font {
        Font.system(size: size, weight: .semibold, design: .monospaced)
    }
}

// MARK: - Text Styles

extension View {
    /// Apply large title style
    func beastLargeTitleStyle() -> some View {
        self.font(.beastLargeTitle)
    }

    /// Apply title style
    func beastTitleStyle() -> some View {
        self.font(.beastTitle)
    }

    /// Apply headline style
    func beastHeadlineStyle() -> some View {
        self.font(.beastHeadline)
    }

    /// Apply body style
    func beastBodyStyle() -> some View {
        self.font(.beastBody)
    }

    /// Apply caption style
    func beastCaptionStyle() -> some View {
        self
            .font(.beastCaption)
            .foregroundStyle(.secondary)
    }

    /// Apply number style
    func beastNumberStyle(size: CGFloat = 32) -> some View {
        self.font(.beastNumber(size))
    }
}

// MARK: - Label Styles

struct BeastLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon
                .foregroundStyle(.beastPrimary)
            configuration.title
        }
    }
}

extension LabelStyle where Self == BeastLabelStyle {
    static var beast: BeastLabelStyle {
        BeastLabelStyle()
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            Group {
                Text("Large Title")
                    .font(.beastLargeTitle)

                Text("Title")
                    .font(.beastTitle)

                Text("Title 2")
                    .font(.beastTitle2)

                Text("Title 3")
                    .font(.beastTitle3)

                Text("Headline")
                    .font(.beastHeadline)

                Text("Body text for regular content")
                    .font(.beastBody)

                Text("Callout text")
                    .font(.beastCallout)

                Text("Subheadline")
                    .font(.beastSubheadline)

                Text("Footnote")
                    .font(.beastFootnote)

                Text("Caption text")
                    .font(.beastCaption)
            }

            Divider()

            Group {
                Text("135")
                    .font(.beastLargeNumber)

                Text("8 reps")
                    .font(.beastMediumNumber)

                Text("1:30")
                    .font(.beastTimer(40))
            }
        }
        .padding()
    }
}
