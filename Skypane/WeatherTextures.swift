//
//  WeatherTextures.swift
//  Skypane
//

import AppKit
import SpriteKit

/// Particle textures drawn in code, shared by every scene.
enum WeatherTextures {
    /// A round flake with a bright center that fades out softly at the edge.
    static let softFlake: SKTexture = makeTexture(width: 32, height: 32) { canvas in
        drawSoftBlob(in: canvas)
    }

    /// Clumpy flakes made of a few overlapping soft blobs, for larger flakes and falling chunks.
    static let flakeClumps: [SKTexture] = clumpLayouts.map { blobs in
        makeTexture(width: 32, height: 32) { canvas in
            for blob in blobs {
                let diameter = blob.diameter * canvas.width
                let blobRect = CGRect(
                    x: blob.centerX * canvas.width - diameter / 2,
                    y: blob.centerY * canvas.height - diameter / 2,
                    width: diameter,
                    height: diameter
                )
                drawSoftBlob(in: blobRect)
            }
        }
    }

    /// A thin streak, solid at the bottom and fading toward the top, for raindrops.
    static let rainStreak: SKTexture = makeTexture(width: 4, height: 64) { canvas in
        let streakGradient = NSGradient(
            starting: NSColor(white: 1, alpha: 0.9),
            ending: NSColor(white: 1, alpha: 0)
        )
        streakGradient?.draw(in: NSBezierPath(roundedRect: canvas, xRadius: 2, yRadius: 2), angle: 90)
    }

    /// A wide, very soft cloud puff for fog.
    static let fogPuff: SKTexture = makeTexture(width: 256, height: 128) { canvas in
        let puffGradient = NSGradient(colorsAndLocations:
            (NSColor(white: 1, alpha: 0.85), 0),
            (NSColor(white: 1, alpha: 0.45), 0.5),
            (NSColor(white: 1, alpha: 0), 1)
        )
        puffGradient?.draw(in: NSBezierPath(ovalIn: canvas), relativeCenterPosition: .zero)
    }

    /// A round, faint fog blob, tiled in a grid so the cursor can wipe patches of fog away.
    static let fogBlob: SKTexture = makeTexture(width: 128, height: 128) { canvas in
        let blobGradient = NSGradient(colorsAndLocations:
            (NSColor(white: 1, alpha: 0.7), 0),
            (NSColor(white: 1, alpha: 0.35), 0.5),
            (NSColor(white: 1, alpha: 0), 1)
        )
        blobGradient?.draw(in: NSBezierPath(ovalIn: canvas), relativeCenterPosition: .zero)
    }

    /// A thin, flattened ring for raindrop ripples on the Dock.
    static let rippleRing: SKTexture = makeTexture(width: 64, height: 16) { canvas in
        NSColor.white.setStroke()
        let ringPath = NSBezierPath(ovalIn: canvas.insetBy(dx: 2, dy: 2))
        ringPath.lineWidth = 2
        ringPath.stroke()
    }

    /// A glow that's bright at the bottom and fades upward, rotated to light each screen edge.
    static let edgeGlow: SKTexture = makeTexture(width: 4, height: 64) { canvas in
        let glowGradient = NSGradient(
            starting: NSColor(white: 1, alpha: 1),
            ending: NSColor(white: 1, alpha: 0)
        )
        glowGradient?.draw(in: canvas, angle: 90)
    }

    /// White leaf shapes with a cut-out vein, tinted to autumn colors at runtime.
    static let leaves: [SKTexture] = [
        // A pointed oval leaf.
        makeTexture(width: 32, height: 32) { canvas in
            let leafPath = NSBezierPath()
            leafPath.move(to: CGPoint(x: canvas.midX, y: canvas.minY + 2))
            leafPath.curve(to: CGPoint(x: canvas.midX, y: canvas.maxY - 2),
                           controlPoint1: CGPoint(x: canvas.minX - 2, y: canvas.minY + 10),
                           controlPoint2: CGPoint(x: canvas.minX + 6, y: canvas.maxY - 6))
            leafPath.curve(to: CGPoint(x: canvas.midX, y: canvas.minY + 2),
                           controlPoint1: CGPoint(x: canvas.maxX - 6, y: canvas.maxY - 6),
                           controlPoint2: CGPoint(x: canvas.maxX + 2, y: canvas.minY + 10))
            NSColor.white.setFill()
            leafPath.fill()
            cutVein(from: CGPoint(x: canvas.midX, y: canvas.minY + 2), to: CGPoint(x: canvas.midX, y: canvas.maxY - 6))
        },
        // A rounder three-lobed leaf.
        makeTexture(width: 32, height: 32) { canvas in
            NSColor.white.setFill()
            NSBezierPath(ovalIn: CGRect(x: 9, y: 10, width: 14, height: 20)).fill()
            for (lobeX, lobeAngle) in [(CGFloat(4), CGFloat(35)), (CGFloat(28), CGFloat(-35))] {
                let lobeTransform = AffineTransform(translationByX: lobeX, byY: 13)
                var rotation = AffineTransform(rotationByDegrees: lobeAngle)
                rotation.append(lobeTransform)
                let lobePath = NSBezierPath(ovalIn: CGRect(x: -6, y: -4, width: 12, height: 16))
                lobePath.transform(using: rotation)
                lobePath.fill()
            }
            cutVein(from: CGPoint(x: canvas.midX, y: canvas.minY + 1), to: CGPoint(x: canvas.midX, y: canvas.maxY - 5))
        },
    ]

    /// A warm glowing dot for fireflies.
    static let fireflyGlow: SKTexture = makeTexture(width: 32, height: 32) { canvas in
        let glowGradient = NSGradient(colorsAndLocations:
            (NSColor(calibratedRed: 1.0, green: 1.0, blue: 0.75, alpha: 1), 0),
            (NSColor(calibratedRed: 0.85, green: 1.0, blue: 0.35, alpha: 0.55), 0.25),
            (NSColor(calibratedRed: 0.7, green: 0.95, blue: 0.2, alpha: 0), 1)
        )
        glowGradient?.draw(in: NSBezierPath(ovalIn: canvas), relativeCenterPosition: .zero)
    }

    /// A rounded petal with a small notch at the tip, tinted pink (or any color) at runtime.
    static let petal: SKTexture = makeTexture(width: 24, height: 32) { canvas in
        let petalPath = NSBezierPath()
        petalPath.move(to: CGPoint(x: canvas.midX, y: canvas.minY + 1))
        petalPath.curve(to: CGPoint(x: canvas.midX - 3, y: canvas.maxY - 2),
                        controlPoint1: CGPoint(x: canvas.minX - 4, y: canvas.minY + 12),
                        controlPoint2: CGPoint(x: canvas.minX + 1, y: canvas.maxY))
        petalPath.line(to: CGPoint(x: canvas.midX, y: canvas.maxY - 6))
        petalPath.line(to: CGPoint(x: canvas.midX + 3, y: canvas.maxY - 2))
        petalPath.curve(to: CGPoint(x: canvas.midX, y: canvas.minY + 1),
                        controlPoint1: CGPoint(x: canvas.maxX - 1, y: canvas.maxY),
                        controlPoint2: CGPoint(x: canvas.maxX + 4, y: canvas.minY + 12))
        NSColor.white.setFill()
        petalPath.fill()
    }

    /// A small solid rectangle for confetti, tinted at runtime.
    static let confettiPiece: SKTexture = makeTexture(width: 8, height: 12) { canvas in
        NSColor.white.setFill()
        NSBezierPath(roundedRect: canvas, xRadius: 1, yRadius: 1).fill()
    }

    /// A clear bubble with a thin rim and a small highlight.
    static let bubble: SKTexture = makeTexture(width: 48, height: 48) { canvas in
        let rimGradient = NSGradient(colorsAndLocations:
            (NSColor(white: 1, alpha: 0.05), 0),
            (NSColor(white: 1, alpha: 0.12), 0.75),
            (NSColor(white: 1, alpha: 0.7), 0.95),
            (NSColor(white: 1, alpha: 0), 1)
        )
        rimGradient?.draw(in: NSBezierPath(ovalIn: canvas), relativeCenterPosition: .zero)
        NSColor(white: 1, alpha: 0.8).setFill()
        NSBezierPath(ovalIn: CGRect(x: canvas.width * 0.25, y: canvas.height * 0.6, width: 8, height: 6)).fill()
    }

    /// A soft horizontal band of light for auroras: clear at the top and bottom edges, bright in the middle.
    static let auroraRibbon: SKTexture = makeTexture(width: 256, height: 128) { canvas in
        let bandGradient = NSGradient(colorsAndLocations:
            (NSColor(white: 1, alpha: 0), 0),
            (NSColor(white: 1, alpha: 0.55), 0.35),
            (NSColor(white: 1, alpha: 0.25), 0.7),
            (NSColor(white: 1, alpha: 0), 1)
        )
        bandGradient?.draw(in: canvas, angle: 90)
        // Fade the ends so ribbons blend into each other.
        NSGraphicsContext.current?.compositingOperation = .destinationIn
        let endFade = NSGradient(colorsAndLocations:
            (NSColor(white: 1, alpha: 0), 0),
            (NSColor(white: 1, alpha: 1), 0.2),
            (NSColor(white: 1, alpha: 1), 0.8),
            (NSColor(white: 1, alpha: 0), 1)
        )
        endFade?.draw(in: canvas, angle: 0)
        NSGraphicsContext.current?.compositingOperation = .sourceOver
    }

    // MARK: - Drawing helpers

    /// Erases a thin line, used for leaf veins.
    private static func cutVein(from start: CGPoint, to end: CGPoint) {
        NSGraphicsContext.current?.compositingOperation = .clear
        let veinPath = NSBezierPath()
        veinPath.move(to: start)
        veinPath.line(to: end)
        veinPath.lineWidth = 1
        veinPath.stroke()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
    }

    /// Positions of the blobs in each clump, in unit coordinates of the texture.
    private static let clumpLayouts: [[(centerX: CGFloat, centerY: CGFloat, diameter: CGFloat)]] = [
        [(0.50, 0.50, 0.62), (0.30, 0.62, 0.42), (0.68, 0.38, 0.44)],
        [(0.45, 0.45, 0.56), (0.66, 0.60, 0.46), (0.34, 0.30, 0.36), (0.62, 0.30, 0.32)],
        [(0.50, 0.56, 0.52), (0.30, 0.40, 0.42), (0.70, 0.44, 0.40)],
    ]

    /// Fills an oval with white that's solid in the middle and fades to clear at the edge.
    private static func drawSoftBlob(in blobRect: CGRect) {
        let blobGradient = NSGradient(colorsAndLocations:
            (NSColor(white: 1, alpha: 1), 0),
            (NSColor(white: 1, alpha: 0.8), 0.45),
            (NSColor(white: 1, alpha: 0), 1)
        )
        blobGradient?.draw(in: NSBezierPath(ovalIn: blobRect), relativeCenterPosition: .zero)
    }

    private static func makeTexture(width: CGFloat, height: CGFloat, draw: @escaping (CGRect) -> Void) -> SKTexture {
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { canvas in
            draw(canvas)
            return true
        }
        return SKTexture(image: image)
    }
}
