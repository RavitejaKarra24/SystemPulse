import SwiftUI

/// Bounded, inspectable history drawn in one canvas instead of a view per sample.
struct GraphCard: View {
    let history: [Double]
    let metric: Theme.MetricType
    let formatter: (Double) -> String
    var height: CGFloat = 105
    var secondaryHistory: [Double]? = nil
    var secondaryColor: Color? = nil
    var fixedCeiling: Double? = nil
    var title: String = "Activity"
    var primaryLabel: String = "Current"
    var secondaryLabel: String = ""
    // Keep these after the legacy parameters: callers rely on synthesized initializer order.
    var timedHistory: MetricHistory? = nil
    var secondaryTimedHistory: MetricHistory? = nil

    @State private var sampleCount = 60
    @State private var frozen: [Double]?
    @State private var frozenSecondary: [Double]?
    @State private var hoverFraction: Double?

    private var accent: Color { Theme.accent(for: metric) }

    var body: some View {
        if let timedHistory {
            TimedGraphCard(
                history: timedHistory, secondaryHistory: secondaryTimedHistory,
                accent: accent, secondaryColor: secondaryColor, formatter: formatter,
                height: height, fixedCeiling: fixedCeiling, title: title,
                primaryLabel: primaryLabel, secondaryLabel: secondaryLabel,
                maximumContinuousGap: metric == .power ? 15 : 4.5)
        } else {
            legacyBody
        }
    }

    private var legacyBody: some View {
        let values = Array((frozen ?? history).suffix(sampleCount)).map { $0.isFinite ? max(0, $0) : 0 }
        let secondary = Array((frozen != nil ? frozenSecondary ?? [] : secondaryHistory ?? []).suffix(sampleCount))
            .map { $0.isFinite ? max(0, $0) : 0 }
        let ceiling = max(fixedCeiling ?? (max(values.max() ?? 0, secondary.max() ?? 0) * 1.15), 1)
        let index = selectedIndex(count: values.count)
        let current = index.map { values[$0] } ?? values.last ?? 0

        return GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(title.uppercased())
                        .font(Theme.smallCaption).tracking(1)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    HStack(spacing: 2) {
                        ForEach([20, 60], id: \.self) { count in
                            Button {
                                sampleCount = count
                                hoverFraction = nil
                            } label: {
                                Text("\(count)").font(Theme.smallCaption)
                                    .foregroundStyle(sampleCount == count ? Theme.textPrimary : Theme.textSecondary)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(sampleCount == count ? accent.opacity(0.22) : .clear, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .help("Show the latest \(count) samples")
                            .accessibilityLabel("Last \(count) samples")
                            .accessibilityAddTraits(sampleCount == count ? .isSelected : [])
                        }
                    }
                    .background(Theme.insetFill, in: Capsule())
                    Button {
                        if frozen == nil {
                            frozen = history
                            frozenSecondary = secondaryHistory
                        } else {
                            frozen = nil
                            frozenSecondary = nil
                        }
                        hoverFraction = nil
                    } label: {
                        Image(systemName: frozen == nil ? "pause.fill" : "play.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(accent)
                            .frame(width: 26, height: 26)
                            .background(accent.opacity(0.14), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help(frozen == nil ? "Freeze this chart to inspect it" : "Resume live chart")
                    .accessibilityLabel(frozen == nil ? "Freeze chart" : "Resume live chart")
                }

                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(values.isEmpty ? "—" : formatter(current))
                        .font(Theme.rounded(26, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(index.map { "SAMPLE \($0 + 1)" } ?? (frozen == nil ? "LIVE" : "FROZEN"))
                        .font(Theme.smallCaption)
                        .foregroundStyle(accent)
                    Spacer(minLength: 0)
                }

                GeometryReader { geo in
                    Canvas { context, size in
                        let plot = CGRect(x: 0, y: 5, width: size.width, height: max(1, size.height - 10))
                        for level in [0.0, 0.5, 1.0] {
                            let y = plot.maxY - plot.height * level
                            var grid = Path()
                            grid.move(to: CGPoint(x: plot.minX, y: y))
                            grid.addLine(to: CGPoint(x: plot.maxX, y: y))
                            context.stroke(grid, with: .color(Theme.gridLine), lineWidth: 0.5)
                        }
                        draw(values, color: accent, ceiling: ceiling, plot: plot, context: &context, filled: true)
                        if let color = secondaryColor {
                            draw(
                                secondary, color: color, ceiling: ceiling, plot: plot, context: &context, filled: false)
                        }
                        if let index {
                            let point = point(
                                index: index, value: values[index], count: values.count, ceiling: ceiling, plot: plot)
                            var rule = Path()
                            rule.move(to: CGPoint(x: point.x, y: plot.minY))
                            rule.addLine(to: CGPoint(x: point.x, y: plot.maxY))
                            context.stroke(
                                rule, with: .color(Theme.textSecondary), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            context.fill(
                                Path(ellipseIn: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)),
                                with: .color(Theme.textPrimary))
                        }
                    }
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location): hoverFraction = min(1, max(0, location.x / max(geo.size.width, 1)))
                        case .ended: hoverFraction = nil
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        Text(formatter(ceiling))
                            .font(Theme.smallCaption).foregroundStyle(Theme.textTertiary)
                            .padding(4).background(Theme.cardFill.opacity(0.9), in: Capsule())
                            .allowsHitTesting(false)
                    }
                    .overlay {
                        if values.isEmpty {
                            Text("Waiting for samples…")
                                .font(Theme.captionFont).foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                .frame(height: height)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(title), \(values.count) samples")
                .accessibilityValue(
                    values.isEmpty
                        ? "Waiting for samples"
                        : "\(primaryLabel) \(formatter(current)), average \(formatter(values.reduce(0, +) / Double(values.count))), peak \(formatter(values.max() ?? 0))"
                )

                if !secondary.isEmpty, let color = secondaryColor {
                    HStack {
                        seriesLabel(primaryLabel, value: formatter(current), color: accent)
                        Spacer()
                        let secondaryIndex = index.map { max(0, secondary.count - values.count + $0) }
                        seriesLabel(
                            secondaryLabel,
                            value: formatter(
                                secondaryIndex.flatMap { secondary.indices.contains($0) ? secondary[$0] : nil }
                                    ?? secondary.last ?? 0), color: color)
                    }
                }
                HStack {
                    Text("\(values.count) samples")
                    Spacer()
                    Text("Avg \(formatter(values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)))")
                    Text("·")
                    Text("Peak \(formatter(values.max() ?? 0))")
                }
                .font(Theme.smallCaption).foregroundStyle(Theme.textSecondary).monospacedDigit()
            }
        }
    }

    private func selectedIndex(count: Int) -> Int? {
        guard let hoverFraction, count > 0 else { return nil }
        return min(count - 1, max(0, Int((hoverFraction * Double(sampleCount - 1)).rounded()) - (sampleCount - count)))
    }

    private func point(index: Int, value: Double, count: Int, ceiling: Double, plot: CGRect) -> CGPoint {
        CGPoint(
            x: plot.width * Double(sampleCount - count + index) / Double(sampleCount - 1),
            y: plot.maxY - plot.height * min(1, max(0, value / ceiling)))
    }

    private func draw(
        _ values: [Double], color: Color, ceiling: Double, plot: CGRect,
        context: inout GraphicsContext, filled: Bool
    ) {
        guard !values.isEmpty else { return }
        let points = values.enumerated().map {
            point(index: $0.offset, value: $0.element, count: values.count, ceiling: ceiling, plot: plot)
        }
        var line = Path()
        line.addLines(points)
        if filled, let first = points.first, let last = points.last {
            var area = line
            area.addLine(to: CGPoint(x: last.x, y: plot.maxY))
            area.addLine(to: CGPoint(x: first.x, y: plot.maxY))
            area.closeSubpath()
            context.fill(
                area,
                with: .linearGradient(
                    Gradient(colors: [color.opacity(0.16), color.opacity(0.01)]), startPoint: plot.origin,
                    endPoint: CGPoint(x: 0, y: plot.maxY)))
        }
        context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 2.3, lineCap: .round, lineJoin: .round))
        if let last = points.last {
            context.fill(
                Path(ellipseIn: CGRect(x: last.x - 3, y: last.y - 3, width: 6, height: 6)), with: .color(color))
        }
    }

    private func seriesLabel(_ title: String, value: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text("\(title) \(value)").font(Theme.smallCaption).monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

/// Timestamped mode is independent of legacy sample-count state and never mixes the two clocks.
private struct TimedGraphCard: View {
    let history: MetricHistory
    let secondaryHistory: MetricHistory?
    let accent: Color
    let secondaryColor: Color?
    let formatter: (Double) -> String
    let height: CGFloat
    let fixedCeiling: Double?
    let title: String
    let primaryLabel: String
    let secondaryLabel: String
    let maximumContinuousGap: TimeInterval

    @State private var range: HistoryRange = .fiveMinutes
    @State private var frozen: Snapshot?
    @State private var selectedTimestamp: Date?

    private struct Snapshot {
        let history: MetricHistory
        let secondary: MetricHistory?
        let anchor: Date
    }

    var body: some View {
        // Move the live window even if this metric stops receiving readings. No telemetry timer
        // is stopped by freeze, and the frozen branch needs no periodic redraw of its own.
        if let frozen {
            content(snapshot: frozen)
        } else {
            TimelineView(.periodic(from: .now, by: 3)) { _ in
                // Use redraw time, not the last scheduled tick: a parent may deliver a newer
                // observation between timeline ticks and it should be visible immediately.
                content(snapshot: Snapshot(history: history, secondary: secondaryHistory, anchor: Date()))
            }
        }
    }

    private func content(snapshot: Snapshot) -> some View {
        let window = MetricHistoryWindow(history: snapshot.history, range: range, endingAt: snapshot.anchor)
        let secondary = snapshot.secondary?.points(in: range, endingAt: snapshot.anchor) ?? []
        let selection = selectedTimestamp.flatMap { date in window.points.first { $0.timestamp == date } }
        let current = selection ?? window.points.last
        let liveMode =
            current.map {
                snapshot.anchor.timeIntervalSince($0.timestamp) > maximumContinuousGap ? "LAST KNOWN" : "LIVE"
            } ?? "NO DATA"
        let displayMode = selection != nil ? "SELECTED" : (frozen != nil ? "FROZEN" : liveMode)
        let peak = max(window.points.map(\.value).max() ?? 0, secondary.map(\.value).max() ?? 0)
        let paddedPeak = peak < Double.greatestFiniteMagnitude / 1.15 ? peak * 1.15 : peak
        let ceiling = max(1, fixedCeiling.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? paddedPeak)
        let secondaryCurrent =
            selection.flatMap { selected in
                secondary.first { $0.timestamp == selected.timestamp }
            } ?? (selection == nil ? secondary.last : nil)

        return GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(title.uppercased())
                        .font(Theme.smallCaption).tracking(1).foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: 4)
                    HStack(spacing: 2) {
                        ForEach(HistoryRange.allCases) { option in
                            Button {
                                range = option
                                selectedTimestamp = nil
                            } label: {
                                Text(option.label).font(Theme.smallCaption)
                                    .foregroundStyle(range == option ? Theme.textPrimary : Theme.textSecondary)
                                    .padding(.horizontal, 7).padding(.vertical, 4)
                                    .background(range == option ? accent.opacity(0.22) : .clear, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .help("Show the last \(option.label)")
                            .accessibilityLabel(
                                option == .fiveMinutes
                                    ? "Last five minutes" : (option == .oneHour ? "Last hour" : "Last 24 hours")
                            )
                            .accessibilityAddTraits(range == option ? .isSelected : [])
                        }
                    }
                    .background(Theme.insetFill, in: Capsule())
                    Button {
                        frozen = frozen == nil ? snapshot : nil
                        selectedTimestamp = nil
                    } label: {
                        Image(systemName: frozen == nil ? "pause.fill" : "play.fill")
                            .font(.system(size: 10, weight: .bold)).foregroundStyle(accent)
                            .frame(width: 26, height: 26)
                            .background(accent.opacity(0.14), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help(frozen == nil ? "Freeze this chart, not telemetry" : "Resume live chart")
                    .accessibilityLabel(frozen == nil ? "Freeze chart" : "Resume live chart")
                }

                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(current.map { formatter($0.value) } ?? "—")
                        .font(Theme.rounded(26, weight: .bold)).foregroundStyle(Theme.textPrimary)
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                    Text(displayMode)
                        .font(Theme.smallCaption).foregroundStyle(accent)
                    Spacer(minLength: 0)
                }
                if let current {
                    Text(current.timestamp, format: .dateTime.month().day().hour().minute().second())
                        .font(Theme.smallCaption).foregroundStyle(Theme.textSecondary).monospacedDigit()
                }

                TimedMetricPlot(
                    window: window, secondary: secondary, accent: accent, secondaryColor: secondaryColor,
                    ceiling: ceiling, selection: selection, formatter: formatter,
                    maximumContinuousGap: maximumContinuousGap,
                    onHover: { selectedTimestamp = $0?.timestamp }
                )
                .frame(height: height)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "\(title), last \(range.label), \(window.points.count) \(range == .fiveMinutes ? "samples" : "bucket means"), \(frozen == nil ? "live" : "frozen")"
                )
                .accessibilityValue(summary(window.points, current: current, secondary: secondaryCurrent))
                .accessibilityHint(
                    "Adjust to inspect earlier or later observations. Missing measurements are not filled in."
                )
                .accessibilityAdjustableAction { direction in
                    adjust(direction, points: window.points)
                }
                .focusable()
                .onKeyPress(keys: [.leftArrow], phases: .down) { press in
                    guard
                        PanelKeyboardPolicy.allowsNamedKey(
                            modifiers: press.modifiers, isEditingText: false,
                            voiceOverEnabled: PanelKeyboardPolicy.voiceOverIsActive)
                    else { return .ignored }
                    adjust(.decrement, points: window.points)
                    return .handled
                }
                .onKeyPress(keys: [.rightArrow], phases: .down) { press in
                    guard
                        PanelKeyboardPolicy.allowsNamedKey(
                            modifiers: press.modifiers, isEditingText: false,
                            voiceOverEnabled: PanelKeyboardPolicy.voiceOverIsActive)
                    else { return .ignored }
                    adjust(.increment, points: window.points)
                    return .handled
                }
                .onKeyPress(keys: [.escape], phases: .down) { press in
                    guard
                        PanelKeyboardPolicy.allowsNamedKey(
                            modifiers: press.modifiers, isEditingText: false,
                            voiceOverEnabled: PanelKeyboardPolicy.voiceOverIsActive)
                    else { return .ignored }
                    selectedTimestamp = nil
                    return .handled
                }

                HStack {
                    Text(window.startingAt, format: .dateTime.hour().minute())
                    Spacer()
                    Text(window.endingAt, format: .dateTime.hour().minute())
                }
                .font(Theme.smallCaption).foregroundStyle(Theme.textTertiary).monospacedDigit()
                .accessibilityHidden(true)

                if secondaryColor != nil {
                    HStack {
                        HStack(spacing: 5) {
                            Circle().fill(accent).frame(width: 5, height: 5).accessibilityHidden(true)
                            Text("\(primaryLabel) \(current.map { formatter($0.value) } ?? "—")")
                        }
                        Spacer()
                        HStack(spacing: 5) {
                            Circle().fill(secondaryColor ?? accent).frame(width: 5, height: 5).accessibilityHidden(true)
                            Text("\(secondaryLabel) \(secondaryCurrent.map { formatter($0.value) } ?? "—")")
                        }
                    }
                    .font(Theme.smallCaption).foregroundStyle(Theme.textSecondary).monospacedDigit()
                }
                HStack {
                    Text("\(window.points.count) \(range == .fiveMinutes ? "samples" : "means")")
                    Spacer(minLength: 4)
                    Text("\(range == .fiveMinutes ? "Avg" : "Avg mean") \(mean(window.points).map(formatter) ?? "—")")
                    Text("·")
                    Text(
                        "\(range == .fiveMinutes ? "Peak" : "Peak mean") \(window.points.map(\.value).max().map(formatter) ?? "—")"
                    )
                }
                .font(Theme.smallCaption).foregroundStyle(Theme.textSecondary).monospacedDigit()
                Text(
                    range == .fiveMinutes
                        ? "Gaps over \(String(format: "%g", maximumContinuousGap))s are unconnected"
                        : "\(Int(range.bucketDuration))s sample means · points unconnected"
                )
                .font(Theme.smallCaption).foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private func mean(_ points: [TimedMetricSample]) -> Double? {
        guard !points.isEmpty else { return nil }
        return points.enumerated().reduce(0) { result, item in
            result + (item.element.value - result) / Double(item.offset + 1)
        }
    }

    private func summary(
        _ points: [TimedMetricSample], current: TimedMetricSample?, secondary: TimedMetricSample?
    ) -> String {
        guard let current else { return "No samples in this window" }
        let time = current.timestamp.formatted(date: .abbreviated, time: .standard)
        let second =
            secondary.map {
                ", \(secondaryLabel) \(formatter($0.value)) at \($0.timestamp.formatted(date: .abbreviated, time: .standard))"
            } ?? ""
        return
            "\(primaryLabel) \(formatter(current.value)) at \(time)\(second), average of displayed points \(mean(points).map(formatter) ?? "—"), peak displayed point \(points.map(\.value).max().map(formatter) ?? "—"). Gaps are unconnected."
    }

    private func adjust(_ direction: AccessibilityAdjustmentDirection, points: [TimedMetricSample]) {
        guard !points.isEmpty else { return }
        let index = selectedTimestamp.flatMap { date in points.firstIndex { $0.timestamp == date } } ?? points.count - 1
        switch direction {
        case .increment: selectedTimestamp = points[min(points.count - 1, index + 1)].timestamp
        case .decrement: selectedTimestamp = points[max(0, index - 1)].timestamp
        @unknown default: break
        }
    }
}

/// Coarse aggregates are discrete dots, not connected lines: even within-bucket gaps must not
/// masquerade as continuous measurements. Raw lines only connect normal app polling intervals.
private struct TimedMetricPlot: View {
    let window: MetricHistoryWindow
    let secondary: [TimedMetricSample]
    let accent: Color
    let secondaryColor: Color?
    let ceiling: Double
    let selection: TimedMetricSample?
    let formatter: (Double) -> String
    let maximumContinuousGap: TimeInterval
    let onHover: (TimedMetricSample?) -> Void

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let plot = CGRect(x: 0, y: 5, width: size.width, height: max(1, size.height - 10))
                for level in [0.0, 0.5, 1.0] {
                    let y = plot.maxY - plot.height * level
                    var grid = Path()
                    grid.move(to: CGPoint(x: plot.minX, y: y))
                    grid.addLine(to: CGPoint(x: plot.maxX, y: y))
                    context.stroke(grid, with: .color(Theme.gridLine), lineWidth: 0.5)
                }
                draw(window.points, color: accent, plot: plot, context: &context)
                if let secondaryColor {
                    draw(secondary, color: secondaryColor, plot: plot, context: &context)
                }
                if let selection {
                    let location = point(selection, plot: plot)
                    var rule = Path()
                    rule.move(to: CGPoint(x: location.x, y: plot.minY))
                    rule.addLine(to: CGPoint(x: location.x, y: plot.maxY))
                    context.stroke(
                        rule, with: .color(Theme.textSecondary), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    context.fill(
                        Path(ellipseIn: CGRect(x: location.x - 4, y: location.y - 4, width: 8, height: 8)),
                        with: .color(Theme.textPrimary))
                }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    onHover(window.nearestSample(to: location.x / max(1, geometry.size.width)))
                case .ended: onHover(nil)
                }
            }
            .overlay(alignment: .topLeading) {
                Text(formatter(ceiling)).font(Theme.smallCaption).foregroundStyle(Theme.textTertiary)
                    .padding(4).background(Theme.cardFill.opacity(0.9), in: Capsule())
                    .allowsHitTesting(false)
            }
            .overlay {
                if window.points.isEmpty {
                    Text("No samples in this window")
                        .font(Theme.captionFont).foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private func point(_ sample: TimedMetricSample, plot: CGRect) -> CGPoint {
        CGPoint(
            x: plot.minX + plot.width * window.fraction(at: sample.timestamp),
            y: plot.maxY - plot.height * min(1, max(0, sample.value / ceiling)))
    }

    private func draw(
        _ samples: [TimedMetricSample], color: Color, plot: CGRect, context: inout GraphicsContext
    ) {
        var line = Path()
        var dots = Path()
        var previous: TimedMetricSample?
        for sample in samples {
            let location = point(sample, plot: plot)
            if window.range == .fiveMinutes, let previous,
                sample.timestamp.timeIntervalSince(previous.timestamp) <= maximumContinuousGap
            {
                line.addLine(to: location)
            } else {
                line.move(to: location)
            }
            dots.addEllipse(in: CGRect(x: location.x - 1.5, y: location.y - 1.5, width: 3, height: 3))
            previous = sample
        }
        context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        context.fill(dots, with: .color(color))
    }
}
