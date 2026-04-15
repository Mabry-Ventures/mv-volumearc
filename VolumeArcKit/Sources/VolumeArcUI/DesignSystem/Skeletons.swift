#if canImport(SwiftUI)
import SwiftUI

// MARK: - Shimmer modifier

public struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0),
                        Color.white.opacity(0.35),
                        Color.white.opacity(0),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .blendMode(.overlay)
                .rotationEffect(.degrees(20))
                .offset(x: phase * 400)
                .animation(
                    reduceMotion
                        ? .linear(duration: 0).repeatCount(1)
                        : .linear(duration: 1.4).repeatForever(autoreverses: false),
                    value: phase
                )
                .allowsHitTesting(false)
            )
            .onAppear {
                guard !reduceMotion else { return }
                phase = 1.5
            }
            .mask(content)
    }
}

public extension View {
    func vaShimmer() -> some View {
        modifier(Shimmer())
    }
}

// MARK: - Skeleton primitives

public struct VASkeletonLine: View {
    private let width: CGFloat?
    private let height: CGFloat

    public init(width: CGFloat? = nil, height: CGFloat = 14) {
        self.width = width
        self.height = height
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(VA.Colors.surfaceTertiary)
            .frame(width: width, height: height)
            .vaShimmer()
    }
}

public struct VASkeletonCircle: View {
    private let size: CGFloat

    public init(size: CGFloat = 48) {
        self.size = size
    }

    public var body: some View {
        Circle()
            .fill(VA.Colors.surfaceTertiary)
            .frame(width: size, height: size)
            .vaShimmer()
    }
}

/// A pre-composed loading card for dashboard and list screens.
public struct VASkeletonCard: View {
    public init() {}

    public var body: some View {
        VACard(style: .flat) {
            VStack(alignment: .leading, spacing: VA.Space.md) {
                HStack(spacing: VA.Space.md) {
                    VASkeletonCircle(size: 44)
                    VStack(alignment: .leading, spacing: VA.Space.xs) {
                        VASkeletonLine(width: 140, height: 14)
                        VASkeletonLine(width: 200, height: 10)
                    }
                    Spacer()
                }
                VASkeletonLine(height: 10)
                VASkeletonLine(width: 180, height: 10)
            }
        }
    }
}

/// A stacked list of skeleton cards to use while a view is loading its first data.
public struct VASkeletonList: View {
    private let count: Int

    public init(count: Int = 3) {
        self.count = count
    }

    public var body: some View {
        VStack(spacing: VA.Space.md) {
            ForEach(0..<count, id: \.self) { _ in
                VASkeletonCard()
            }
        }
    }
}
#endif
