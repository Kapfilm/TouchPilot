import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

struct OriginalCoralIconMaker {
    let resourcesURL: URL
    let iconsetURL: URL

    func run() throws {
        try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: iconsetURL)
        try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

        let master = try renderIcon(size: 1024)
        try writePNG(master, to: resourcesURL.appendingPathComponent("AppIcon.png"))

        var iconImages: [(IconSpec, Data)] = []
        for spec in IconSpec.all {
            let image = try renderIcon(size: spec.pixelSize)
            let pngURL = iconsetURL.appendingPathComponent(spec.fileName)
            try writePNG(image, to: pngURL)
            iconImages.append((spec, try Data(contentsOf: pngURL)))
        }
        try writeICNS(iconImages, to: resourcesURL.appendingPathComponent("AppIcon.icns"))
    }

    private func renderIcon(size: Int) throws -> CGImage {
        let outputSize = NSSize(width: size, height: size)
        let scale = CGFloat(size) / 1024
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: size,
            pixelsHigh: size,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: size * 4,
            bitsPerPixel: 32
        ), let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw NSError(domain: "OriginalCoralIconMaker", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot create icon bitmap"])
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        defer { NSGraphicsContext.restoreGraphicsState() }

        graphicsContext.cgContext.setShouldAntialias(true)
        graphicsContext.cgContext.setAllowsAntialiasing(true)
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: outputSize).fill()

        // Keep the colored tile inside the canvas so Finder/Launchpad can show a
        // soft macOS-style cast shadow instead of making the icon look pasted on.
        // One shared macOS tile geometry for every display context. Keeping the
        // artwork inside the 1024 canvas gives Finder room for the classic
        // floating shadow and avoids the oversized iOS-icon look.
        let iconRect = NSRect(x: 106 * scale, y: 126 * scale, width: 812 * scale, height: 812 * scale)
        // Launchpad presents the catalog artwork without the extra visual
        // rounding seen in Finder previews, so use the classic macOS icon
        // corner proportion directly in the source tile.
        let cornerRadius = 227 * scale
        let iconPath = NSBezierPath(roundedRect: iconRect, xRadius: cornerRadius, yRadius: cornerRadius)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.36)
        shadow.shadowBlurRadius = 44 * scale
        shadow.shadowOffset = NSSize(width: 0, height: -22 * scale)
        shadow.set()
        NSColor.black.withAlphaComponent(0.34).setFill()
        iconPath.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        iconPath.addClip()
        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 1.00, green: 0.44, blue: 0.36, alpha: 1.00),
            NSColor(calibratedRed: 0.99, green: 0.23, blue: 0.22, alpha: 1.00)
        ])
        gradient?.draw(in: iconRect, angle: -90)
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        let artworkTransform = NSAffineTransform()
        artworkTransform.translateX(by: 512 * scale, yBy: 524 * scale)
        artworkTransform.scale(by: 800.0 / 780.0)
        artworkTransform.translateX(by: -512 * scale, yBy: -526 * scale)
        artworkTransform.concat()
        let faceShadow = NSShadow()
        faceShadow.shadowColor = NSColor.black.withAlphaComponent(0.52)
        faceShadow.shadowBlurRadius = 29 * scale
        faceShadow.shadowOffset = NSSize(width: 11 * scale, height: -18 * scale)
        faceShadow.set()
        NSColor.white.withAlphaComponent(0.98).setFill()
        NSBezierPath(ovalIn: NSRect(x: 433 * scale, y: 565 * scale, width: 128 * scale, height: 128 * scale)).fill()
        NSBezierPath(ovalIn: NSRect(x: 599 * scale, y: 523 * scale, width: 128 * scale, height: 128 * scale)).fill()

        let smile = NSBezierPath()
        smile.move(to: NSPoint(x: 306 * scale, y: 330 * scale))
        smile.curve(
            to: NSPoint(x: 668 * scale, y: 484 * scale),
            controlPoint1: NSPoint(x: 444 * scale, y: 306 * scale),
            controlPoint2: NSPoint(x: 572 * scale, y: 366 * scale)
        )
        smile.lineWidth = 27 * scale
        smile.lineCapStyle = .round
        NSColor.white.withAlphaComponent(0.98).setStroke()
        smile.stroke()
        NSGraphicsContext.restoreGraphicsState()

        // Directional system-style specular rims: upper-left and lower-right.
        // They follow the existing tile geometry without changing its radius.
        let rimInset = 1.5 * scale
        let rimRect = iconRect.insetBy(dx: rimInset, dy: rimInset)
        let rimRadius = cornerRadius - rimInset
        let kappa: CGFloat = 0.5522847498
        let upperLeftRim = NSBezierPath()
        upperLeftRim.move(to: NSPoint(x: rimRect.minX, y: rimRect.midY + 34 * scale))
        upperLeftRim.line(to: NSPoint(x: rimRect.minX, y: rimRect.maxY - rimRadius))
        upperLeftRim.curve(
            to: NSPoint(x: rimRect.minX + rimRadius, y: rimRect.maxY),
            controlPoint1: NSPoint(x: rimRect.minX, y: rimRect.maxY - rimRadius + rimRadius * kappa),
            controlPoint2: NSPoint(x: rimRect.minX + rimRadius - rimRadius * kappa, y: rimRect.maxY)
        )
        upperLeftRim.line(to: NSPoint(x: rimRect.midX - 34 * scale, y: rimRect.maxY))

        let lowerRightRim = NSBezierPath()
        lowerRightRim.move(to: NSPoint(x: rimRect.maxX, y: rimRect.midY - 34 * scale))
        lowerRightRim.line(to: NSPoint(x: rimRect.maxX, y: rimRect.minY + rimRadius))
        lowerRightRim.curve(
            to: NSPoint(x: rimRect.maxX - rimRadius, y: rimRect.minY),
            controlPoint1: NSPoint(x: rimRect.maxX, y: rimRect.minY + rimRadius - rimRadius * kappa),
            controlPoint2: NSPoint(x: rimRect.maxX - rimRadius + rimRadius * kappa, y: rimRect.minY)
        )
        lowerRightRim.line(to: NSPoint(x: rimRect.midX + 34 * scale, y: rimRect.minY))
        func drawTaperedRim(_ path: NSBezierPath, start: NSPoint, end: NSPoint) {
            let context = graphicsContext.cgContext
            context.saveGState()
            context.addPath(path.cgPath)
            context.setLineWidth(2.2 * scale)
            context.setLineCap(.round)
            context.replacePathWithStrokedPath()
            context.clip()

            let peakAlpha: CGFloat = 0.78
            let colors = [
                NSColor.white.withAlphaComponent(0).cgColor,
                NSColor.white.withAlphaComponent(peakAlpha).cgColor,
                NSColor.white.withAlphaComponent(0).cgColor
            ] as CFArray
            let locations: [CGFloat] = [0, 0.5, 1]
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: locations
            ) {
                context.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: start.x, y: start.y),
                    end: CGPoint(x: end.x, y: end.y),
                    options: []
                )
            }
            context.restoreGState()
        }

        drawTaperedRim(
            upperLeftRim,
            start: NSPoint(x: rimRect.minX, y: rimRect.midY + 34 * scale),
            end: NSPoint(x: rimRect.midX - 34 * scale, y: rimRect.maxY)
        )
        drawTaperedRim(
            lowerRightRim,
            start: NSPoint(x: rimRect.maxX, y: rimRect.midY - 34 * scale),
            end: NSPoint(x: rimRect.midX + 34 * scale, y: rimRect.minY)
        )

        NSGraphicsContext.saveGraphicsState()
        iconPath.addClip()
        let topHighlight = NSGradient(colors: [
            NSColor.white.withAlphaComponent(0.30),
            NSColor.white.withAlphaComponent(0.08),
            NSColor.white.withAlphaComponent(0.00)
        ])
        topHighlight?.draw(
            in: NSRect(
                x: iconRect.minX,
                y: iconRect.maxY - 96 * scale,
                width: iconRect.width,
                height: 96 * scale
            ),
            angle: -90
        )
        NSGraphicsContext.restoreGraphicsState()

        guard let output = bitmap.cgImage else {
            throw NSError(domain: "OriginalCoralIconMaker", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot render icon"])
        }
        return output
    }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw NSError(domain: "OriginalCoralIconMaker", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cannot create PNG destination"])
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "OriginalCoralIconMaker", code: 4, userInfo: [NSLocalizedDescriptionKey: "Cannot write PNG"])
        }
    }

    private func writeICNS(_ images: [(IconSpec, Data)], to url: URL) throws {
        var body = Data()
        for (spec, pngData) in images {
            guard let type = spec.icnsType else { continue }
            body.appendFourCC(type)
            body.appendUInt32(UInt32(pngData.count + 8))
            body.append(pngData)
        }

        var output = Data()
        output.appendFourCC("icns")
        output.appendUInt32(UInt32(body.count + 8))
        output.append(body)
        try output.write(to: url)
    }
}

struct IconSpec {
    let baseSize: Int
    let scale: Int

    var pixelSize: Int { baseSize * scale }
    var fileName: String {
        scale == 1 ? "icon_\(baseSize)x\(baseSize).png" : "icon_\(baseSize)x\(baseSize)@\(scale)x.png"
    }

    var icnsType: String? {
        switch (baseSize, scale) {
        case (16, 1): return "icp4"
        case (16, 2): return "ic11"
        case (32, 1): return "icp5"
        case (32, 2): return "ic12"
        case (128, 1): return "ic07"
        case (128, 2): return "ic13"
        case (256, 1): return "ic08"
        case (256, 2): return "ic14"
        case (512, 1): return "ic09"
        case (512, 2): return "ic10"
        default: return nil
        }
    }

    static let all = [
        IconSpec(baseSize: 16, scale: 1),
        IconSpec(baseSize: 16, scale: 2),
        IconSpec(baseSize: 32, scale: 1),
        IconSpec(baseSize: 32, scale: 2),
        IconSpec(baseSize: 128, scale: 1),
        IconSpec(baseSize: 128, scale: 2),
        IconSpec(baseSize: 256, scale: 1),
        IconSpec(baseSize: 256, scale: 2),
        IconSpec(baseSize: 512, scale: 1),
        IconSpec(baseSize: 512, scale: 2)
    ]
}

extension Data {
    mutating func appendFourCC(_ value: String) {
        precondition(value.utf8.count == 4)
        append(contentsOf: value.utf8)
    }

    mutating func appendUInt32(_ value: UInt32) {
        var bigEndianValue = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndianValue) { append(contentsOf: $0) }
    }
}

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: make_original_coral_icon.swift <resources-dir> <iconset-dir>\n", stderr)
    exit(2)
}

do {
    try OriginalCoralIconMaker(
        resourcesURL: URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true),
        iconsetURL: URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
    ).run()
} catch {
    fputs("Icon generation failed: \(error)\n", stderr)
    exit(1)
}
