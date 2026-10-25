import AppKit

@main @MainActor
struct MenuBarIconRegression {
    static func require(_ condition: Bool, _ message: String) {
        if !condition { fatalError(message) }
    }
    static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let image = MenuBarIcon.makeImage()
        require(image.isTemplate, "System must own the foreground color")
        require(image.accessibilityDescription == "Mini Typeless", "Missing accessible name")
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        var brightness: [Double] = []
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let button = NSButton(frame: NSRect(x: 0, y: 0, width: 32, height: 24))
            button.isBordered = false
            button.title = ""
            button.imagePosition = .imageOnly
            button.image = image
            button.contentTintColor = nil
            button.appearance = NSAppearance(named: appearance)
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 48, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            bitmap.size = button.bounds.size
            button.cacheDisplay(in: button.bounds, to: bitmap)
            var light = 0.0, alpha = 0.0
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    let c = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                    alpha += c.alphaComponent
                    light += (c.redComponent + c.greenComponent + c.blueComponent) / 3 * c.alphaComponent
                    if x == 0 || y == 0 || x == bitmap.pixelsWide - 1 || y == bitmap.pixelsHigh - 1 {
                        require(c.alphaComponent < 0.01, "Artwork clips outside button")
                    }
                }
            }
            require(alpha > 20 && alpha < 700, "Empty glyph or unwanted opaque tile")
            brightness.append(light / alpha)
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("\(name).png"))
        }
        require(brightness[0] < 0.35 && brightness[1] > 0.70, "Template did not adapt: \(brightness)")
        print("PASS: original transparent template, no edge clipping; offscreen AppKit light/dark luminance \(brightness). Live menu bar still needs user confirmation.")
    }
}
