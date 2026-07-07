// Generates the macOS DMG install-window background:
//   black fill · grey right-arrow centered · "SONORITY" wordmark at the bottom.
// The .app and Applications icons are laid on top by create-dmg (see the
// `mac github` lane / release.yml). Run once and commit the output PNGs:
//
//   swift tool/dmg_background.swift
//     → macos/dmg/background.png      (600×400)
//     → macos/dmg/background@2x.png   (1200×800)
//
// Coordinates are in points (600×400 window). AppKit's origin is bottom-left, so
// a y measured from the window TOP (as create-dmg uses for icons) is 400 - y here.

import AppKit

let W = 600.0, H = 430.0
// Match create-dmg's icon centers (y measured from top): app 150,165 · drop 450,165.
let iconTopY = 165.0
let rowY = H - iconTopY // AppKit y of the icon row center
// Extra bottom margin (window is 430 tall) keeps the wordmark clear of Finder's
// path/status bar, which some users have enabled and which overlaps the bottom.

func draw(scale: Int, to path: String) {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(W) * scale, pixelsHigh: Int(H) * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H) // logical size → CTM scales to pixels

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Black background.
    NSColor.black.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: W, height: H)).fill()

    // Grey thin right-pointing arrow, centered between the two icon slots (x≈300):
    // a stroked shaft plus an open chevron head.
    let grey = NSColor(white: 0.45, alpha: 1)
    grey.setStroke()
    let cx = W / 2, cy = rowY
    let len = 96.0, head = 22.0
    let tail = cx - len / 2, tip = cx + len / 2
    let arrow = NSBezierPath()
    arrow.lineWidth = 3
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: tail, y: cy)) // shaft
    arrow.line(to: NSPoint(x: tip, y: cy))
    arrow.move(to: NSPoint(x: tip - head, y: cy + head)) // chevron head
    arrow.line(to: NSPoint(x: tip, y: cy))
    arrow.line(to: NSPoint(x: tip - head, y: cy - head))
    arrow.stroke()

    // "SONORITY" wordmark, centered near the bottom.
    let text = "SONORITY" as NSString
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 26, weight: .semibold),
        .foregroundColor: NSColor(white: 0.75, alpha: 1),
        .kern: 6.0,
    ]
    let size = text.size(withAttributes: attrs)
    text.draw(at: NSPoint(x: (W - size.width) / 2, y: 62), withAttributes: attrs)

    NSGraphicsContext.restoreGraphicsState()

    let png = rep.representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: path))
    print("wrote \(path) (\(Int(W) * scale)×\(Int(H) * scale))")
}

let dir = "macos/dmg"
try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
draw(scale: 1, to: "\(dir)/background.png")
draw(scale: 2, to: "\(dir)/background@2x.png")
