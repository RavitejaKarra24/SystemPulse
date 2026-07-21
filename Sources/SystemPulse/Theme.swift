import SwiftUI

/// Design system for SystemPulse — premium dark workstation aesthetic.
enum Theme {

    // MARK: - Core Palette

    static let bgTop    = Color(red: 0.09, green: 0.09, blue: 0.12)
    static let bgMid    = Color(red: 0.07, green: 0.07, blue: 0.10)
    static let bgBottom = Color(red: 0.05, green: 0.05, blue: 0.07)

    static let ambientGlow = Color(red: 0.35, green: 0.40, blue: 0.95).opacity(0.12)

    static let cardFill       = Color.white.opacity(0.055)
    static let cardFillRaised = Color.white.opacity(0.08)
    static let cardStroke     = Color.white.opacity(0.10)
    static let cardHighlight  = Color.white.opacity(0.14)
    static let insetFill      = Color.black.opacity(0.28)
    static let insetStroke    = Color.white.opacity(0.06)
    static let rowHover       = Color.white.opacity(0.05)

    // MARK: - Accent colors

    static let accentBlue    = Color(red: 0.32, green: 0.58, blue: 1.00)
    static let accentBlueDim = Color(red: 0.32, green: 0.58, blue: 1.00).opacity(0.30)
    static let accentViolet  = Color(red: 0.62, green: 0.48, blue: 1.00)
    static let accentTeal    = Color(red: 0.28, green: 0.86, blue: 0.78)
    static let accentOrange  = Color(red: 1.00, green: 0.68, blue: 0.28)
    static let accentGreen   = Color(red: 0.35, green: 0.90, blue: 0.58)
    static let accentRed     = Color(red: 1.00, green: 0.40, blue: 0.42)
    static let accentYellow  = Color(red: 1.00, green: 0.84, blue: 0.30)

    static let textPrimary   = Color.white.opacity(0.96)
    static let textSecondary = Color.white.opacity(0.68)
    static let textTertiary  = Color.white.opacity(0.42)

    static let gridLine     = Color.white.opacity(0.10)
    static let trackColor   = Color.white.opacity(0.09)
    static let dividerColor = Color.white.opacity(0.08)

    // MARK: - Metric coloring

    enum MetricType {
        case cpu, memory, network, disk
    }

    static func accent(for metric: MetricType) -> Color {
        switch metric {
        case .cpu:     return accentBlue
        case .memory:  return accentViolet
        case .network: return accentTeal
        case .disk:    return accentOrange
        }
    }

    static func accentSoft(for metric: MetricType) -> Color {
        accent(for: metric).opacity(0.18)
    }

    static func barGradient(for metric: MetricType) -> LinearGradient {
        let c = accent(for: metric)
        return LinearGradient(
            colors: [c.opacity(0.35), c.opacity(0.75), c],
            startPoint: .bottom, endPoint: .top
        )
    }

    static func ringGradient(for metric: MetricType) -> AngularGradient {
        let c = accent(for: metric)
        return AngularGradient(
            gradient: Gradient(colors: [
                c.opacity(0.40),
                c,
                c.opacity(0.90),
                c.opacity(0.55)
            ]),
            center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)
        )
    }

    static func pillGradient(for metric: MetricType) -> LinearGradient {
        let c = accent(for: metric)
        return LinearGradient(
            colors: [c, c.opacity(0.82)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    static func loadColor(_ percent: Double) -> Color {
        switch LoadColor.forPercent(percent) {
        case .critical: return accentRed
        case .warning:  return accentOrange
        case .normal:   return accentGreen
        }
    }

    static func pressureColor(_ pressure: MemoryPressure) -> Color {
        switch pressure {
        case .normal:   return accentGreen
        case .warning:  return accentOrange
        case .critical: return accentRed
        }
    }

    // MARK: - Layout

    static let popoverWidth: CGFloat  = 372
    static let cardCorner: CGFloat    = 18
    static let pillCorner: CGFloat    = 14
    static let outerPadding: CGFloat  = 14
    static let sectionGap: CGFloat    = 12

    // MARK: - Typography

    static func rounded(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static let titleFont     = rounded(16, weight: .semibold)
    static let tabFont       = rounded(12.5, weight: .semibold)
    static let bigValueFont  = rounded(28, weight: .bold)
    static let heroFont      = rounded(22, weight: .bold)
    static let valueFont     = rounded(15, weight: .semibold)
    static let rowNameFont   = rounded(13, weight: .medium)
    static let rowValueFont  = rounded(13, weight: .semibold)
    static let captionFont   = rounded(11, weight: .regular)
    static let smallCaption  = rounded(10, weight: .medium)
    static let badgeFont     = rounded(10, weight: .semibold)
    static let buttonFont    = rounded(13, weight: .semibold)
    static let monoCaption   = Font.system(size: 11, weight: .medium, design: .monospaced)

    // MARK: - Animation

    static let smoothSpring  = Animation.spring(response: 0.4, dampingFraction: 0.85)
    static let quickSpring   = Animation.spring(response: 0.28, dampingFraction: 0.8)
    static let snappy        = Animation.spring(response: 0.22, dampingFraction: 0.86)
    static let pushTransition = AnyTransition.asymmetric(
        insertion: .move(edge: .trailing).combined(with: .opacity),
        removal: .move(edge: .leading).combined(with: .opacity)
    )
}

// MARK: - Reusable background

struct AppBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.bgTop, Theme.bgMid, Theme.bgBottom],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [Theme.ambientGlow, .clear],
                center: .top,
                startRadius: 10,
                endRadius: 220
            )
            .blendMode(.plusLighter)
        }
    }
}

// MARK: - Card container

struct GlassCard<Content: View>: View {
    let content: Content
    var padding: CGFloat = 16
    var elevated: Bool = false

    init(padding: CGFloat = 16, elevated: Bool = false, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.elevated = elevated
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                        .fill(elevated ? Theme.cardFillRaised : Theme.cardFill)

                    RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Theme.cardHighlight, Theme.cardStroke.opacity(0.3), Theme.cardStroke],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                }
            )
    }
}

// MARK: - Pill buttons

struct FilledPillButton: View {
    let title: String
    let color: Color
    var isDestructive: Bool = false
    let action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.buttonFont)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [color, color.opacity(0.82)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: color.opacity(isHovered ? 0.48 : 0.35), radius: isHovered ? 10 : 8, y: 2)
                )
                .scaleEffect(isPressed ? 0.97 : 1)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .animation(Theme.snappy, value: isHovered)
        .animation(Theme.snappy, value: isPressed)
    }
}

struct OutlinePillButton: View {
    let title: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.buttonFont)
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    ZStack {
                        Capsule().fill(Color.white.opacity(isHovered ? 0.08 : 0.04))
                        Capsule().strokeBorder(Color.white.opacity(isHovered ? 0.24 : 0.16), lineWidth: 1)
                    }
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(Theme.snappy, value: isHovered)
    }
}

// MARK: - Usage micro-bar

struct UsageBar: View {
    let value: Double
    let maxValue: Double
    let color: Color
    var width: CGFloat = 44

    private var fraction: CGFloat {
        guard maxValue > 0 else { return 0 }
        return CGFloat(min(1, max(0, value / maxValue)))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.trackColor)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.7), color],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(4, geo.size.width * fraction))
            }
        }
        .frame(width: width, height: 4)
        .animation(Theme.quickSpring, value: fraction)
    }
}

// MARK: - Section label

struct SectionLabel: View {
    let text: String
    var trailing: String? = nil

    var body: some View {
        HStack {
            Text(text.uppercased())
                .font(Theme.smallCaption)
                .tracking(0.6)
                .foregroundStyle(Theme.textTertiary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(Theme.smallCaption)
                    .foregroundStyle(Theme.textTertiary)
                    .monospacedDigit()
            }
        }
    }
}

// MARK: - Toast banner

struct ToastBanner: View {
    let toast: ToastMessage

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: toast.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(toast.isError ? Theme.accentRed : Theme.accentGreen)
            Text(toast.text)
                .font(Theme.captionFont)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - Inset surface helper

struct InsetSurface: ViewModifier {
    var cornerRadius: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Theme.insetFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Theme.insetStroke, lineWidth: 1)
                    )
            )
    }
}

extension View {
    func insetSurface(cornerRadius: CGFloat = 12) -> some View {
        modifier(InsetSurface(cornerRadius: cornerRadius))
    }
}
