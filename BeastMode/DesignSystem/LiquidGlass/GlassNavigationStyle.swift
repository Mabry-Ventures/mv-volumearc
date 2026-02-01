import SwiftUI

/// Custom navigation bar styling for the Liquid Glass design system
struct GlassNavigationStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

extension View {
    /// Apply glass navigation bar styling
    func glassNavigation() -> some View {
        modifier(GlassNavigationStyle())
    }
}

/// A glass-style segmented control
struct GlassSegmentedPicker<SelectionValue: Hashable, Content: View>: View {
    @Binding var selection: SelectionValue
    let content: Content

    init(selection: Binding<SelectionValue>, @ViewBuilder content: () -> Content) {
        self._selection = selection
        self.content = content()
    }

    var body: some View {
        Picker("", selection: $selection) {
            content
        }
        .pickerStyle(.segmented)
        .padding(4)
        .glassBackground(cornerRadius: 12)
    }
}

/// A glass-style menu button
struct GlassMenu<Label: View, Content: View>: View {
    let content: Content
    let label: Label

    init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.content = content()
        self.label = label()
    }

    var body: some View {
        Menu {
            content
        } label: {
            label
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassBackground(cornerRadius: 12)
        }
    }
}

/// Glass-style tab indicator
struct GlassTabIndicator: View {
    var body: some View {
        Capsule()
            .fill(.ultraThinMaterial)
            .frame(height: 3)
    }
}

/// A glass-style sheet background
struct GlassSheetBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .presentationBackground(.ultraThinMaterial)
            .presentationCornerRadius(24)
    }
}

extension View {
    /// Apply glass sheet background styling
    func glassSheet() -> some View {
        modifier(GlassSheetBackground())
    }
}

/// A glass-style floating action button
struct GlassFloatingButton: View {
    let icon: String
    let action: () -> Void
    var size: CGFloat = 56

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background {
                    Circle()
                        .fill(Color.beastPrimary.gradient)
                }
                .shadow(color: .beastPrimary.opacity(0.4), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(GlassButtonStyle())
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ZStack {
            LinearGradient(
                colors: [.beastPrimary.opacity(0.2), .beastSecondary.opacity(0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 30) {
                GlassSegmentedPicker(selection: .constant(0)) {
                    Text("Week").tag(0)
                    Text("Month").tag(1)
                    Text("Year").tag(2)
                }
                .padding(.horizontal)

                GlassMenu {
                    Button("Option 1") {}
                    Button("Option 2") {}
                    Button("Option 3") {}
                } label: {
                    HStack {
                        Text("Select")
                        Image(systemName: "chevron.down")
                    }
                }

                Spacer()

                HStack {
                    Spacer()
                    GlassFloatingButton(icon: "plus") {}
                        .padding()
                }
            }
        }
        .navigationTitle("Design System")
        .glassNavigation()
    }
}
