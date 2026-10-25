import AppKit

/// Original B3 Short waveform-to-i mark, not an SF Symbol.
/// Only alpha carries meaning: the menu bar supplies its own foreground color.
@MainActor
enum MenuBarIcon {
    static func makeImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 24, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            NSColor.black.setStroke()
            let wave = NSBezierPath()
            wave.lineWidth = 1.55
            wave.lineCapStyle = .round
            wave.lineJoinStyle = .round
            wave.move(to: NSPoint(x: 2, y: 5.5))
            // Three unequal crests and two troughs read as an audio waveform.
            wave.curve(to: NSPoint(x: 4, y: 11.2), controlPoint1: NSPoint(x: 2.8, y: 8.2), controlPoint2: NSPoint(x: 3.3, y: 11.2))
            wave.curve(to: NSPoint(x: 6.4, y: 2.8), controlPoint1: NSPoint(x: 5.1, y: 11.2), controlPoint2: NSPoint(x: 5.4, y: 2.8))
            wave.curve(to: NSPoint(x: 9.5, y: 14.8), controlPoint1: NSPoint(x: 7.7, y: 2.8), controlPoint2: NSPoint(x: 8.3, y: 14.8))
            wave.curve(to: NSPoint(x: 12.3, y: 3.8), controlPoint1: NSPoint(x: 10.8, y: 14.8), controlPoint2: NSPoint(x: 10.9, y: 3.8))
            wave.curve(to: NSPoint(x: 14.8, y: 8.8), controlPoint1: NSPoint(x: 13.4, y: 3.8), controlPoint2: NSPoint(x: 13.9, y: 8.8))
            // Settle directly onto the short baseline: no extra dip or crest.
            wave.curve(to: NSPoint(x: 17.8, y: 5.5), controlPoint1: NSPoint(x: 15.9, y: 8.8), controlPoint2: NSPoint(x: 16.3, y: 5.5))
            wave.line(to: NSPoint(x: 21.1, y: 5.5))
            wave.curve(to: NSPoint(x: 21.6, y: 6), controlPoint1: NSPoint(x: 21.5, y: 5.5), controlPoint2: NSPoint(x: 21.6, y: 5.6))
            wave.line(to: NSPoint(x: 21.6, y: 9.8))
            wave.stroke()
            NSBezierPath(ovalIn: NSRect(x: 20.75, y: 11.15, width: 1.7, height: 1.7)).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Mini Typeless"
        return image
    }
}
