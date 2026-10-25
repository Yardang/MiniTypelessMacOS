import AppKit

/// Original wave-to-i mark derived from our approved artwork, not an SF Symbol.
/// Only alpha carries meaning: the menu bar supplies its own foreground color.
@MainActor
enum MenuBarIcon {
    static func makeImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 24, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            NSColor.black.setStroke()
            let wave = NSBezierPath()
            wave.lineWidth = 1.65
            wave.lineCapStyle = .round
            wave.lineJoinStyle = .round
            wave.move(to: NSPoint(x: 2, y: 6))
            wave.curve(to: NSPoint(x: 6, y: 11.2), controlPoint1: NSPoint(x: 4.1, y: 6), controlPoint2: NSPoint(x: 4.6, y: 11.2))
            wave.curve(to: NSPoint(x: 10, y: 4.8), controlPoint1: NSPoint(x: 7.6, y: 11.2), controlPoint2: NSPoint(x: 8.1, y: 4.8))
            wave.curve(to: NSPoint(x: 12.8, y: 6.7), controlPoint1: NSPoint(x: 11.2, y: 4.8), controlPoint2: NSPoint(x: 11.6, y: 6.7))
            wave.curve(to: NSPoint(x: 16.3, y: 5.1), controlPoint1: NSPoint(x: 14.2, y: 6.7), controlPoint2: NSPoint(x: 14.8, y: 5.1))
            wave.line(to: NSPoint(x: 20.5, y: 5.1))
            wave.curve(to: NSPoint(x: 21.2, y: 5.8), controlPoint1: NSPoint(x: 21.0, y: 5.1), controlPoint2: NSPoint(x: 21.2, y: 5.3))
            wave.line(to: NSPoint(x: 21.2, y: 10.5))
            wave.stroke()
            NSBezierPath(ovalIn: NSRect(x: 20.35, y: 12.65, width: 1.7, height: 1.7)).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Mini Typeless"
        return image
    }
}
