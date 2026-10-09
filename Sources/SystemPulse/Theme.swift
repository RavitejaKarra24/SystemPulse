import SwiftUI

/// Quiet, native surfaces with color reserved for measurements and status.
enum Theme {

    // MARK: - Core Palette

    static let background = Color(nsColor: .windowBackgroundColor)
    static let cardFill = Color(nsColor: .controlBackgroundColor)
    static let cardFillRaised = Color(nsColor: .textBackgroundColor)
    static let cardStroke = Color(nsColor: .separatorColor)
    static let insetFill = Color.primary.opacity(0.035)
    static let insetStroke = Color(nsColor: .separatorColor)
    static let rowHover = Color.primary.opacity(0.055)

    // MARK: - Accent colors

    static let accentBlue = Color(nsColor: .systemBlue)
    static let accentBlueDim = accentBlue.opacity(0.20)
    static let accentViolet = Color(nsColor: .systemPurple)
    static let accentTeal = Color(nsColor: .systemTeal)
    static let accentOrange = Color(nsColor: .systemOrange)
    static let accentGreen = Color(nsColor: .systemGreen)
    static let accentRed = Color(nsColor: .systemRed)
    static let accentYellow = Color(nsColor: .systemOrange)

    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let textTertiary = Color(nsColor: .secondaryLabelColor)

    static let gridLine = Color.primary.opacity(0.09)
    static let trackColor = Color.primary.opacity(0.07)
    static let dividerColor = Color(nsColor: .separatorColor)

    // MARK: - Metric coloring

    enum MetricType {
        case cpu, memory, network, disk, power
    }

    static func accent(for metric: MetricType) -> Color {
        switch metric {
        case .cpu: return accentBlue
        case .memory: return accentViolet
        case .network: return accentTeal
        case .disk: return accentOrange
        case .power: return accentGreen
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
                c.opacity(0.55),
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
        case .warning: return accentOrange
        case .normal: return accentGreen
        }
    }

    static func pressureColor(_ pressure: MemoryPressure) -> Color {
        switch pressure {
        case .normal: return accentGreen
        case .warning: return accentOrange
        case .critical: return accentRed
        }
    }

    // MARK: - Layout

    static let popoverWidth: CGFloat = 420
    static let cardCorner: CGFloat = 14
    static let pillCorner: CGFloat = 10
    static let outerPadding: CGFloat = 20
    static let sectionGap: CGFloat = 14

    // MARK: - Typography

    static func rounded(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static let titleFont = rounded(16, weight: .semibold)
    static let tabFont = rounded(10.5, weight: .medium)
    static let bigValueFont = rounded(28, weight: .bold)
    static let heroFont = rounded(22, weight: .bold)
    static let valueFont = rounded(15, weight: .semibold)
    static let rowNameFont = rounded(13, weight: .medium)
    static let rowValueFont = rounded(13, weight: .semibold)
    static let captionFont = rounded(11, weight: .regular)
    static let smallCaption = rounded(10, weight: .medium)
    static let badgeFont = rounded(10, weight: .semibold)
    static let buttonFont = rounded(13, weight: .semibold)
    static let monoCaption = Font.system(size: 11, weight: .medium, design: .monospaced)

    // MARK: - Animation

    static let pageAnimation = Animation.easeInOut(duration: 0.20)
    static let smoothSpring = Animation.spring(response: 0.4, dampingFraction: 0.85)
    static let quickSpring = Animation.spring(response: 0.28, dampingFraction: 0.8)
    static let snappy = Animation.spring(response: 0.22, dampingFraction: 0.86)
    static let pushTransition = AnyTransition.asymmetric(
        insertion: .move(edge: .trailing).combined(with: .opacity),
        removal: .move(edge: .leading).combined(with: .opacity)
    )
}

// MARK: - Reusable background

struct AppBackground: View {
    var body: some View {
        Theme.background
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
                        .strokeBorder(Theme.cardStroke, lineWidth: 1)
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

    var body: some View {
        Button(role: isDestructive ? .destructive : nil, action: action) {
            Text(title)
                .font(Theme.buttonFont)
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    color.opacity(isHovered ? 0.18 : 0.10), in: RoundedRectangle(cornerRadius: Theme.pillCorner)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.pillCorner).strokeBorder(
                        color.opacity(0.24), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibleControlFocus(cornerRadius: Theme.pillCorner)
        .onHover { isHovered = $0 }
        .animation(Theme.snappy, value: isHovered)
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
                        RoundedRectangle(cornerRadius: Theme.pillCorner).fill(
                            isHovered ? Theme.rowHover : Theme.insetFill)
                        RoundedRectangle(cornerRadius: Theme.pillCorner).strokeBorder(
                            Theme.cardStroke, lineWidth: 1)
                    }
                )
        }
        .buttonStyle(.plain)
        .accessibleControlFocus(cornerRadius: Theme.pillCorner)
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
                    .frame(width: geo.size.width * fraction)
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
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: toast.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(toast.isError ? Theme.accentRed : Theme.accentGreen)
                Text(toast.isError ? "Action failed" : "Status")
                    .font(Theme.rowNameFont).foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 4)
                if let onDismiss {
                    Button("Dismiss", action: onDismiss)
                        .controlSize(.small)
                }
            }
            if toast.isError {
                ScrollView { messageText }.frame(maxHeight: 110)
            } else {
                messageText
            }
        }
        .padding(14)
        .frame(maxWidth: Theme.popoverWidth - 40, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12).fill(.regularMaterial)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12).strokeBorder(
                Theme.cardStroke, lineWidth: 1)
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var messageText: some View {
        Text(toast.text)
            .font(Theme.captionFont).foregroundStyle(Theme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
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
                            .strokeBorder(
                                Theme.insetStroke, lineWidth: 1)
                    )
            )
    }
}

/// Observe the native button's focus without an extra focus stop or key handler.
struct AccessibleControlFocus: ViewModifier {
    var cornerRadius: CGFloat = 8
    @FocusState private var focused: Bool
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content.focused($focused)
            .overlay {
                ControlFocusOutline(isFocused: focused && isEnabled, cornerRadius: cornerRadius)
                    .allowsHitTesting(false)
            }
    }
}

struct ControlFocusOutline: View {
    let isFocused: Bool
    var cornerRadius: CGFloat = 8
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 2)
            .opacity(isFocused ? 1 : 0)
    }
}

extension View {
    func accessibleControlFocus(cornerRadius: CGFloat = 8) -> some View {
        modifier(AccessibleControlFocus(cornerRadius: cornerRadius))
    }

    func insetSurface(cornerRadius: CGFloat = 12) -> some View {
        modifier(InsetSurface(cornerRadius: cornerRadius))
    }
}
