import AppKit

/// Draws compact menu-bar status artwork for SystemPulse.
enum MenuBarRenderer {

    static func image(
        cpu: Double,
        memory: Double,
        netIn: Double,
        netOut: Double,
        style: Preferences.MenuBarStyle,
        showNetwork: Bool
    ) -> NSImage {
        switch style {
        case .iconOnly:
            return iconOnlyImage(cpu: cpu, memory: memory)
        case .gauges:
            return gaugesImage(cpu: cpu, memory: memory, netIn: netIn, netOut: netOut, showNetwork: showNetwork)
        case .compact, .detailed:
            // Text is applied separately; still provide a small pulse icon.
            return iconOnlyImage(cpu: cpu, memory: memory)
        }
    }

    static func title(
        cpu: Double,
        memory: Double,
        netIn: Double,
        netOut: Double,
        style: Preferences.MenuBarStyle,
        showNetwork: Bool
    ) -> NSAttributedString {
        let color = NSColor.labelColor
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]

        switch style {
        case .iconOnly, .gauges:
            return NSAttributedString(string: "", attributes: attrs)
        case .compact:
            var text = String(format: "%.0f%%  %.0f%%", cpu, memory)
            if showNetwork {
                text += "  " + shortRate(netIn + netOut)
            }
            return NSAttributedString(string: text, attributes: attrs)
        case .detailed:
            var text = String(format: "CPU %.0f%%  MEM %.0f%%", cpu, memory)
            if showNetwork {
                text += String(format: "  ↓%@ ↑%@", shortRate(netIn), shortRate(netOut))
            }
            return NSAttributedString(string: text, attributes: attrs)
        }
    }

    // MARK: - Drawing

    private static func iconOnlyImage(cpu: Double, memory: Double) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let inset = NSRect(x: 1, y: 1, width: 16, height: 16)
            let path = NSBezierPath(roundedRect: inset, xRadius: 4, yRadius: 4)
            NSColor.labelColor.withAlphaComponent(0.12).setFill()
            path.fill()

            // Two vertical meters
            drawMeter(in: NSRect(x: 4, y: 3, width: 4, height: 12), value: cpu / 100)
            drawMeter(in: NSRect(x: 10, y: 3, width: 4, height: 12), value: memory / 100)
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func gaugesImage(
        cpu: Double,
        memory: Double,
        netIn: Double,
        netOut: Double,
        showNetwork: Bool
    ) -> NSImage {
        let width: CGFloat = showNetwork ? 72 : 52
        let size = NSSize(width: width, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            // CPU bar
            drawLabeledBar(x: 0, label: "C", value: cpu / 100)
            // MEM bar
            drawLabeledBar(x: 26, label: "M", value: memory / 100)

            if showNetwork {
                let netLevel = min(1.0, (netIn + netOut) / (2 * 1_048_576)) // scale ~2 MB/s
                drawLabeledBar(x: 52, label: "N", value: netLevel)
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func drawLabeledBar(x: CGFloat, label: String, value: Double) {
        let labelRect = NSRect(x: x, y: 2, width: 8, height: 14)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 8, weight: .bold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
        (label as NSString).draw(in: labelRect, withAttributes: attrs)

        let track = NSRect(x: x + 9, y: 4, width: 14, height: 10)
        let trackPath = NSBezierPath(roundedRect: track, xRadius: 2, yRadius: 2)
        NSColor.labelColor.withAlphaComponent(0.15).setFill()
        trackPath.fill()

        let filledHeight = max(2, track.height * CGFloat(min(1, max(0, value))))
        let fill = NSRect(
            x: track.minX,
            y: track.minY,
            width: track.width,
            height: filledHeight
        )
        let fillPath = NSBezierPath(roundedRect: fill, xRadius: 2, yRadius: 2)
        NSColor.labelColor.setFill()
        fillPath.fill()
    }

    private static func drawMeter(in rect: NSRect, value: Double) {
        let track = NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5)
        NSColor.labelColor.withAlphaComponent(0.18).setFill()
        track.fill()

        let h = max(2, rect.height * CGFloat(min(1, max(0, value))))
        let fillRect = NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: h)
        let fill = NSBezierPath(roundedRect: fillRect, xRadius: 1.5, yRadius: 1.5)
        NSColor.labelColor.setFill()
        fill.fill()
    }

    private static func shortRate(_ bytesPerSec: Double) -> String {
        if bytesPerSec >= 1_048_576 {
            return String(format: "%.1fM", bytesPerSec / 1_048_576)
        }
        if bytesPerSec >= 1024 {
            return String(format: "%.0fK", bytesPerSec / 1024)
        }
        return String(format: "%.0fB", max(0, bytesPerSec))
    }
}
