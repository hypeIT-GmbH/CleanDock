#!/usr/bin/env swift
// Renders the CleanDock app icon: three stacked Dock bars cycling into each
// other (two circular arrows), the active middle bar raised and glossy -
// the app's profile switching in one picture.
//
// Produces the full-bleed glyph layers for the Icon Composer document
// (App/Resources/AppIcon.icon). Xcode compiles that document into the
// macOS 26 appearance variants (default/dark/clear/tinted) plus the classic
// fallback icon for older systems - no separate asset-catalog PNG set.
//
// Usage: swift Scripts/generate-icon.swift <icon-assets-dir>

import AppKit

/// The dark glyph covers the default and dark appearances; the tinted one is
/// the pure grayscale mono source the system derives the clear (glass) and
/// tinted appearances from.
enum IconStyle {
    case dark, tinted
}

let arguments = CommandLine.arguments
let iconAssetsPath = arguments.count > 1 ? arguments[1] : "App/Resources/AppIcon.icon/Assets"
let iconAssetsURL = URL(fileURLWithPath: iconAssetsPath, isDirectory: true)
try? FileManager.default.createDirectory(at: iconAssetsURL, withIntermediateDirectories: true)

// MARK: - Palette

struct BarPalette {
    let fillTop: NSColor
    let fillBottom: NSColor
    let rimTop: NSColor
    let rimBottom: NSColor
    let tileTop: NSColor
    let tileBottom: NSColor
    let accentTileTop: NSColor
    let accentTileBottom: NSColor
}

struct Palette {
    let arrow: NSColor
    let arrowBright: NSColor
    let dot: NSColor
    let active: BarPalette
    let recessed: BarPalette
}

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func palette(for style: IconStyle) -> Palette {
    switch style {
    case .dark:
        return Palette(
            arrow: color(0x8E8E96),
            arrowBright: color(0xDCDCE2),
            dot: NSColor.white.withAlphaComponent(0.95),
            active: BarPalette(
                fillTop: color(0x303036),
                fillBottom: color(0x18191C),
                rimTop: NSColor.white.withAlphaComponent(0.55),
                rimBottom: NSColor.white.withAlphaComponent(0.07),
                tileTop: color(0x7E7E86),
                tileBottom: color(0x53535B),
                accentTileTop: color(0xACACB4),
                accentTileBottom: color(0x7C7C84)
            ),
            recessed: BarPalette(
                fillTop: color(0x1D1D21),
                fillBottom: color(0x121215),
                rimTop: NSColor.white.withAlphaComponent(0.13),
                rimBottom: NSColor.white.withAlphaComponent(0.03),
                tileTop: color(0x3B3B41),
                tileBottom: color(0x28282D),
                accentTileTop: color(0x3B3B41),
                accentTileBottom: color(0x28282D)
            )
        )
    case .tinted:
        return Palette(
            arrow: color(0xDADADA),
            arrowBright: .white,
            dot: .white,
            active: BarPalette(
                fillTop: color(0x7C7C7C),
                fillBottom: color(0x5E5E5E),
                rimTop: .white,
                rimBottom: color(0x969696),
                tileTop: color(0xE4E4E4),
                tileBottom: color(0xBEBEBE),
                accentTileTop: .white,
                accentTileBottom: color(0xE0E0E0)
            ),
            recessed: BarPalette(
                fillTop: color(0x505050),
                fillBottom: color(0x404040),
                rimTop: color(0x828282),
                rimBottom: color(0x565656),
                tileTop: color(0x767676),
                tileBottom: color(0x606060),
                accentTileTop: color(0x767676),
                accentTileBottom: color(0x606060)
            )
        )
    }
}

// MARK: - Geometry (1024 canvas, AppKit bottom-left origin)

struct Bar {
    let center: NSPoint
    let width: CGFloat
    let height: CGFloat
    let tileWidths: [CGFloat]
    let tileHeights: [CGFloat]
    let tileGap: CGFloat
    /// Vertical offset of the tile row from the bar center (positive = up),
    /// leaving room for the page dot in the active bar.
    let tileLift: CGFloat
    let showsDot: Bool
    let isActive: Bool
}

let bars: [Bar] = [
    Bar(center: NSPoint(x: 512, y: 1024 - 304), width: 540, height: 150,
        tileWidths: [96, 96, 96], tileHeights: [96, 96, 96], tileGap: 62,
        tileLift: 0, showsDot: false, isActive: false),
    Bar(center: NSPoint(x: 512, y: 1024 - 720), width: 540, height: 150,
        tileWidths: [96, 96, 96], tileHeights: [96, 96, 96], tileGap: 62,
        tileLift: 0, showsDot: false, isActive: false),
    Bar(center: NSPoint(x: 512, y: 1024 - 512), width: 606, height: 206,
        tileWidths: [116, 148, 116], tileHeights: [116, 134, 116], tileGap: 42,
        tileLift: 10, showsDot: true, isActive: true)
]
let accentTileIndex = 1

// Wider than the outer bars, narrower than the active bar: the arcs emerge
// beside the outer bars while the gap between both arcs spans the middle.
let circleCenter = NSPoint(x: 512, y: 512)
let circleRadius: CGFloat = 352
let arrowLineWidth: CGFloat = 11

// MARK: - Drawing helpers

func withShadow(_ shadowColor: NSColor, blur: CGFloat, offsetY: CGFloat, _ draw: () -> Void) {
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = shadowColor
    shadow.shadowBlurRadius = blur
    shadow.shadowOffset = NSSize(width: 0, height: offsetY)
    shadow.set()
    draw()
    NSGraphicsContext.current?.restoreGraphicsState()
}

func clipped(to path: NSBezierPath, _ draw: () -> Void) {
    NSGraphicsContext.current?.saveGraphicsState()
    path.addClip()
    draw()
    NSGraphicsContext.current?.restoreGraphicsState()
}

/// One curved cycle arrow: a clockwise arc from `startAngle` to `endAngle`
/// (degrees) that fades in from the tail, with a swept head at the end.
func drawCycleArrow(startAngle: CGFloat, endAngle: CGFloat, palette: Palette, scale: CGFloat) {
    let center = NSPoint(x: circleCenter.x * scale, y: circleCenter.y * scale)
    let radius = circleRadius * scale

    // Fading tail: butt-capped segments (round caps would overlap and bead
    // at low alpha) with a steep ramp, so the arc materializes out of
    // nothing behind the outer bars and is solid only near the head.
    let segments = 48
    var span = startAngle - endAngle
    if span < 0 { span += 360 }
    let overlap = span / CGFloat(segments) * 0.02
    for index in 0..<segments {
        let from = startAngle - span * CGFloat(index) / CGFloat(segments)
        let to = startAngle - span * CGFloat(index + 1) / CGFloat(segments) - overlap
        let progress = CGFloat(index + 1) / CGFloat(segments)
        // Never fully invisible: the tail stays as a faint trace the whole
        // way, brightening steadily toward the head.
        let alpha = 0.12 + 0.88 * pow(progress, 1.6)
        let segment = NSBezierPath()
        segment.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: from,
            endAngle: to,
            clockwise: true
        )
        segment.lineWidth = arrowLineWidth * scale
        segment.lineCapStyle = .butt
        palette.arrow.withAlphaComponent(alpha).setStroke()
        segment.stroke()
    }

    // Swept head: the base sits slightly behind the arc end so the tip
    // reads as pulled forward along the rotation.
    let radians = endAngle * .pi / 180
    let tip = NSPoint(
        x: center.x + radius * cos(radians),
        y: center.y + radius * sin(radians)
    )
    let tangent = NSPoint(x: sin(radians), y: -cos(radians))     // clockwise
    let normal = NSPoint(x: cos(radians), y: sin(radians))
    let length = 44 * scale
    let halfWidth = 21 * scale
    let base = NSPoint(x: tip.x - tangent.x * length * 0.16, y: tip.y - tangent.y * length * 0.16)

    let head = NSBezierPath()
    head.move(to: NSPoint(x: tip.x + tangent.x * length, y: tip.y + tangent.y * length))
    head.line(to: NSPoint(x: base.x + normal.x * halfWidth, y: base.y + normal.y * halfWidth))
    head.line(to: tip)
    head.line(to: NSPoint(x: base.x - normal.x * halfWidth, y: base.y - normal.y * halfWidth))
    head.close()
    palette.arrowBright.setFill()
    head.fill()
}

func drawBar(_ bar: Bar, style: IconStyle, palette: Palette, scale: CGFloat) {
    let barPalette = bar.isActive ? palette.active : palette.recessed
    let rect = NSRect(
        x: (bar.center.x - bar.width / 2) * scale,
        y: (bar.center.y - bar.height / 2) * scale,
        width: bar.width * scale,
        height: bar.height * scale
    )
    let radius = bar.height * (bar.isActive ? 0.44 : 0.36) * scale
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    if bar.isActive && style == .dark {
        withShadow(NSColor.black.withAlphaComponent(0.70), blur: 36 * scale, offsetY: -14 * scale) {
            barPalette.fillBottom.setFill()
            path.fill()
        }
    }
    NSGradient(colors: [barPalette.fillTop, barPalette.fillBottom])?
        .draw(in: path, angle: -90)

    // Rim light: brighter along the top edge, fading out at the bottom -
    // this is what lifts the active bar off the background.
    let rim = NSBezierPath(
        roundedRect: rect.insetBy(dx: 1.5 * scale, dy: 1.5 * scale),
        xRadius: radius - 1.5 * scale,
        yRadius: radius - 1.5 * scale
    )
    rim.lineWidth = (bar.isActive ? 3.5 : 2.5) * scale
    barPalette.rimTop.setStroke()
    clipped(to: upperHalf(of: rect)) { rim.stroke() }
    barPalette.rimBottom.setStroke()
    clipped(to: lowerHalf(of: rect)) { rim.stroke() }

    // Gentle top gloss inside the active bar.
    if bar.isActive {
        clipped(to: path) {
            let gloss = NSRect(
                x: rect.minX,
                y: rect.maxY - rect.height * 0.44,
                width: rect.width,
                height: rect.height * 0.44
            )
            NSGradient(colors: [
                NSColor.white.withAlphaComponent(style == .dark ? 0.13 : 0.20),
                NSColor.white.withAlphaComponent(0.0)
            ])?.draw(in: gloss, angle: -90)
        }
    }

    // Tiles, centered as a row; the active bar's center tile is larger and
    // brighter than its siblings.
    let rowWidth = bar.tileWidths.reduce(0, +) + CGFloat(bar.tileWidths.count - 1) * bar.tileGap
    var tileX = bar.center.x - rowWidth / 2
    for (index, tileWidth) in bar.tileWidths.enumerated() {
        let tileHeight = bar.tileHeights[index]
        let tileRect = NSRect(
            x: tileX * scale,
            y: (bar.center.y + bar.tileLift - tileHeight / 2) * scale,
            width: tileWidth * scale,
            height: tileHeight * scale
        )
        let tileRadius = min(tileWidth, tileHeight) * 0.30 * scale
        let tilePath = NSBezierPath(roundedRect: tileRect, xRadius: tileRadius, yRadius: tileRadius)
        let isAccent = bar.isActive && index == accentTileIndex
        let top = isAccent ? barPalette.accentTileTop : barPalette.tileTop
        let bottom = isAccent ? barPalette.accentTileBottom : barPalette.tileBottom
        NSGradient(colors: [top, bottom])?.draw(in: tilePath, angle: -90)

        // Soft top highlight rounds the tiles off.
        clipped(to: tilePath) {
            let highlight = NSRect(
                x: tileRect.minX,
                y: tileRect.maxY - tileRect.height * 0.40,
                width: tileRect.width,
                height: tileRect.height * 0.40
            )
            NSGradient(colors: [
                NSColor.white.withAlphaComponent(isAccent ? 0.30 : 0.18),
                NSColor.white.withAlphaComponent(0.0)
            ])?.draw(in: highlight, angle: -90)
        }
        tileX += tileWidth + bar.tileGap
    }

    // Single page dot centered under the active bar's tiles.
    if bar.showsDot {
        let dotRadius = 9.0 * scale
        let dotCenter = NSPoint(
            x: bar.center.x * scale,
            y: (bar.center.y - bar.height / 2 + 27) * scale
        )
        palette.dot.setFill()
        NSBezierPath(ovalIn: NSRect(
            x: dotCenter.x - dotRadius / 2,
            y: dotCenter.y - dotRadius / 2,
            width: dotRadius,
            height: dotRadius
        )).fill()
    }
}

func upperHalf(of rect: NSRect) -> NSBezierPath {
    NSBezierPath(rect: NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2))
}

func lowerHalf(of rect: NSRect) -> NSBezierPath {
    NSBezierPath(rect: NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height / 2))
}

// MARK: - Icon rendering

func drawIcon(style: IconStyle, canvas: CGFloat) {
    let scale = canvas / 1024
    let palette = palette(for: style)

    // Icon Composer layers span the whole canvas - the system supplies
    // squircle mask, margin and (via the document fill) the background.
    // Scale the slab-relative design up so its proportions inside the
    // final squircle match the classic 824 pt slab exactly.
    let factor: CGFloat = 1024 / 824
    let transform = NSAffineTransform()
    transform.translateX(by: 512 * scale * (1 - factor), yBy: 512 * scale * (1 - factor))
    transform.scale(by: factor)
    transform.concat()

    // The cycle arrows sit behind the bars; the arc tails fade out behind
    // the outer bars and the heads end just before the active bar, so the
    // rotation reads top → middle → bottom → top.
    // Two short side arcs only: each fades in from behind an outer bar's
    // corner and sweeps to its head beside the active bar.
    drawCycleArrow(startAngle: 42, endAngle: 16.5, palette: palette, scale: scale)
    drawCycleArrow(startAngle: 222, endAngle: 196.5, palette: palette, scale: scale)

    // Recessed bars first, the raised active bar on top.
    for bar in bars {
        drawBar(bar, style: style, palette: palette, scale: scale)
    }
}

// MARK: - Output

func render(style: IconStyle, pixels: Int) -> NSBitmapImageRep {
    guard let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Could not create bitmap (\(pixels) px)")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
    drawIcon(style: style, canvas: CGFloat(pixels))
    NSGraphicsContext.restoreGraphicsState()
    return representation
}

func writePNG(_ representation: NSBitmapImageRep, to url: URL) throws {
    guard let png = representation.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode PNG for \(url.lastPathComponent)")
    }
    try png.write(to: url)
    print("Wrote \(url.path)")
}

// Icon Composer layers: full-bleed glyphs without the slab background.
// The dark glyph covers the default and dark appearances (the document fill
// in AppIcon.icon/icon.json provides the dark gradient behind it); the
// grayscale glyph is the mono source the system derives the clear (glass)
// and tinted appearances from, wired up via opacity specializations in the
// same icon.json.
let layers: [(name: String, style: IconStyle)] = [
    ("glyph-dark", .dark),
    ("glyph-tinted", .tinted)
]
for layer in layers {
    try writePNG(
        render(style: layer.style, pixels: 1024),
        to: iconAssetsURL.appendingPathComponent("\(layer.name).png")
    )
}
