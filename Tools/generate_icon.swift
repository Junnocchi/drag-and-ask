// Renders a 1024×1024 PNG app icon to bundle/icon.png.
// Run with: swift Tools/generate_icon.swift
import AppKit

let outPath = "bundle/icon.png"

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size, flipped: false) { rect in
    // Rounded-square accent background.
    let bg = NSColor(calibratedRed: 0.16, green: 0.36, blue: 0.78, alpha: 1.0)
    bg.setFill()
    let path = NSBezierPath(roundedRect: rect, xRadius: 180, yRadius: 180)
    path.fill()

    // SF Symbol on top, white.
    if let baseSymbol = NSImage(systemSymbolName: "text.book.closed.fill", accessibilityDescription: nil) {
        let cfg = NSImage.SymbolConfiguration(pointSize: 540, weight: .semibold, scale: .large)
        if let symbol = baseSymbol.withSymbolConfiguration(cfg) {
            let symSize = symbol.size
            let drawRect = NSRect(
                x: (rect.width - symSize.width) / 2,
                y: (rect.height - symSize.height) / 2 - 10,
                width: symSize.width,
                height: symSize.height
            )
            // Tint to white via image template flag + locked tint.
            NSColor.white.set()
            let tinted = NSImage(size: symSize)
            tinted.lockFocus()
            symbol.draw(in: NSRect(origin: .zero, size: symSize))
            NSColor.white.set()
            NSRect(origin: .zero, size: symSize).fill(using: .sourceAtop)
            tinted.unlockFocus()
            tinted.draw(in: drawRect)
        }
    }

    // Subtle "QA" label at the bottom.
    let label = "D&A"
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 130, weight: .bold),
        .foregroundColor: NSColor.white.withAlphaComponent(0.85)
    ]
    let attr = NSAttributedString(string: label, attributes: attrs)
    let textSize = attr.size()
    let textRect = NSRect(
        x: (rect.width - textSize.width) / 2,
        y: 80,
        width: textSize.width,
        height: textSize.height
    )
    attr.draw(in: textRect)

    return true
}

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:])
else {
    FileHandle.standardError.write(Data("failed to encode PNG\n".utf8))
    exit(1)
}

let url = URL(fileURLWithPath: outPath)
try png.write(to: url)
print("wrote \(outPath) (\(png.count) bytes)")
