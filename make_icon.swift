#!/usr/bin/swift
import AppKit

func makeIcon(size: Int) -> NSImage {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    // Rounded rect clip
    let radius = s * 0.22
    let path = CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                      cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(path)
    ctx.clip()

    // Indigo → purple gradient background
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let colors = [
        CGColor(red: 0.30, green: 0.20, blue: 0.90, alpha: 1.0),
        CGColor(red: 0.58, green: 0.12, blue: 0.82, alpha: 1.0),
    ] as CFArray
    let locs: [CGFloat] = [0.0, 1.0]
    if let grad = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locs) {
        ctx.drawLinearGradient(grad,
                               start: CGPoint(x: 0, y: s),
                               end: CGPoint(x: s, y: 0),
                               options: [])
    }

    // Draw ⌘ glyph centred, white
    let fontSize = s * 0.50
    let font = NSFont.systemFont(ofSize: fontSize, weight: .thin)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
    ]
    let str = NSAttributedString(string: "⌘", attributes: attrs)
    let strSize = str.size()
    let origin = NSPoint(x: (s - strSize.width) / 2,
                         y: (s - strSize.height) / 2)
    str.draw(at: origin)

    image.unlockFocus()
    return image
}

let iconsetPath = "KeyShortcuts.iconset"
try? FileManager.default.createDirectory(atPath: iconsetPath,
                                         withIntermediateDirectories: true)

// (pixel size, filename)
let entries: [(Int, String)] = [
    (16,   "icon_16x16.png"),
    (32,   "icon_16x16@2x.png"),
    (32,   "icon_32x32.png"),
    (64,   "icon_32x32@2x.png"),
    (128,  "icon_128x128.png"),
    (256,  "icon_128x128@2x.png"),
    (256,  "icon_256x256.png"),
    (512,  "icon_256x256@2x.png"),
    (512,  "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

for (size, filename) in entries {
    let img = makeIcon(size: size)
    if let tiff = img.tiffRepresentation,
       let rep  = NSBitmapImageRep(data: tiff),
       let png  = rep.representation(using: .png, properties: [:]) {
        let dest = "\(iconsetPath)/\(filename)"
        try? png.write(to: URL(fileURLWithPath: dest))
        print("  ✓ \(filename)")
    }
}
print("Iconset ready.")
