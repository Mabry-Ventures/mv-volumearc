import SwiftUI

/// A glass-style text field with the Liquid Glass aesthetic
struct GlassTextField: View {
    let placeholder: String
    @Binding var text: String
    var icon: String?
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        HStack(spacing: 12) {
            if let icon {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
            }

            TextField(placeholder, text: $text)
                .keyboardType(keyboardType)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .glassBackground(cornerRadius: 16)
    }
}

/// A glass-style number input field
struct GlassNumberField: View {
    let placeholder: String
    @Binding var value: Double?
    var icon: String?
    var suffix: String?
    var decimalPlaces: Int = 0

    @State private var textValue: String = ""

    var body: some View {
        HStack(spacing: 12) {
            if let icon {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
            }

            TextField(placeholder, text: $textValue)
                .keyboardType(.decimalPad)
                .onChange(of: textValue) { _, newValue in
                    if let number = Double(newValue) {
                        value = number
                    } else if newValue.isEmpty {
                        value = nil
                    }
                }
                .onChange(of: value) { _, newValue in
                    if let number = newValue {
                        if decimalPlaces == 0 {
                            textValue = String(Int(number))
                        } else {
                            textValue = String(format: "%.\(decimalPlaces)f", number)
                        }
                    } else {
                        textValue = ""
                    }
                }

            if let suffix {
                Text(suffix)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .glassBackground(cornerRadius: 16)
        .onAppear {
            if let number = value {
                if decimalPlaces == 0 {
                    textValue = String(Int(number))
                } else {
                    textValue = String(format: "%.\(decimalPlaces)f", number)
                }
            }
        }
    }
}

/// A glass-style text editor for longer text
struct GlassTextEditor: View {
    let placeholder: String
    @Binding var text: String
    var minHeight: CGFloat = 100

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)
            }

            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .background(.clear)
                .frame(minHeight: minHeight)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassBackground(cornerRadius: 16)
    }
}

/// A glass-style search field
struct GlassSearchField: View {
    @Binding var text: String
    var placeholder: String = "Search"
    var onSubmit: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField(placeholder, text: $text)
                .onSubmit {
                    onSubmit?()
                }

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassBackground(cornerRadius: .infinity)
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

        VStack(spacing: 20) {
            GlassTextField(
                placeholder: "Exercise name",
                text: .constant("Bench Press"),
                icon: "dumbbell.fill"
            )

            GlassNumberField(
                placeholder: "Weight",
                value: .constant(135),
                icon: "scalemass.fill",
                suffix: "lbs"
            )

            GlassSearchField(text: .constant(""))

            GlassTextEditor(
                placeholder: "Add notes...",
                text: .constant("")
            )
        }
        .padding()
    }
}
