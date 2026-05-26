#if canImport(SwiftUI)
import SwiftUI

// MARK: - Toast model

public struct VAToast: Identifiable, Equatable {
    public enum Kind {
        case success
        case info
        case warning
        case error

        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .info: return "info.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.octagon.fill"
            }
        }

        var tint: Color {
            switch self {
            case .success: return VA.Colors.success
            case .info: return VA.Colors.info
            case .warning: return VA.Colors.warning
            case .error: return VA.Colors.error
            }
        }

        var accessibilityPrefix: String {
            switch self {
            case .success: return "Success"
            case .info: return "Notice"
            case .warning: return "Warning"
            case .error: return "Error"
            }
        }
    }

    public let id = UUID()
    public let kind: Kind
    public let title: String
    public let message: String?
    public let duration: Double

    public init(kind: Kind, title: String, message: String? = nil, duration: Double = 3.0) {
        self.kind = kind
        self.title = title
        self.message = message
        self.duration = duration
    }

    public static func == (lhs: VAToast, rhs: VAToast) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Presenter

@MainActor
public final class VAToastPresenter: ObservableObject {
    @Published public var current: VAToast?

    private var dismissTask: Task<Void, Never>?

    public init() {}

    public func show(_ toast: VAToast) {
        dismissTask?.cancel()
        current = toast
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(toast.duration * 1_000_000_000))
            await MainActor.run {
                guard let self, self.current?.id == toast.id else { return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    self.current = nil
                }
            }
        }
    }

    public func dismiss() {
        dismissTask?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            current = nil
        }
    }
}

// MARK: - View

public struct VAToastView: View {
    public let toast: VAToast

    public init(toast: VAToast) {
        self.toast = toast
    }

    public var body: some View {
        HStack(alignment: .top, spacing: VA.Space.md) {
            Image(systemName: toast.kind.icon)
                .font(VA.Typography.toastIcon)
                .foregroundStyle(toast.kind.tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title)
                    .font(VA.Typography.headline)
                    .foregroundStyle(VA.Colors.textPrimary)
                if let message = toast.message {
                    Text(message)
                        .font(VA.Typography.footnote)
                        .foregroundStyle(VA.Colors.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(VA.Space.md)
        // Toasts adopt real iOS 26 Liquid Glass with a tint matching the
        // toast kind, so warning/error states read at a glance without losing
        // the system's depth treatment.
        .vaTintedGlassBackground(
            toast.kind.tint.opacity(0.4),
            in: RoundedRectangle(cornerRadius: VA.Radius.md, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: VA.Radius.md, style: .continuous)
                .stroke(toast.kind.tint.opacity(0.3), lineWidth: 1)
        )
        .vaShadow(.md)
        .padding(.horizontal, VA.Space.lg)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(toast.kind.accessibilityPrefix): \(toast.title)\(toast.message.map { ". \($0)" } ?? "")")
        .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: - Overlay modifier

public struct VAToastOverlay: ViewModifier {
    @ObservedObject var presenter: VAToastPresenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let toast = presenter.current {
                VAToastView(toast: toast)
                    .transition(reduceMotion
                        ? .opacity
                        : .asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        )
                    )
                    .gesture(
                        DragGesture(minimumDistance: 10)
                            .onEnded { value in
                                if value.translation.height < -20 {
                                    presenter.dismiss()
                                }
                            }
                    )
                    .padding(.top, VA.Space.sm)
                    .zIndex(1000)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: presenter.current)
    }
}

public extension View {
    /// Attach a toast overlay to the view hierarchy. Scope this high enough
    /// (e.g., on RootDashboardView) so every screen shares a single presenter.
    func vaToastOverlay(_ presenter: VAToastPresenter) -> some View {
        modifier(VAToastOverlay(presenter: presenter))
    }
}
#endif
