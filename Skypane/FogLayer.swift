//
//  FogLayer.swift
//  Skypane
//

import AppKit
import SpriteKit

/// Fog over the desktop: a few large puffs drifting with the wind, plus a grid of soft blobs
/// that the cursor wipes away and that slowly fill back in.
final class FogLayer {
    /// Add this to the scene; it holds every fog sprite.
    let containerNode = SKNode()

    // Drifting puffs give the fog movement.
    private let driftingPuffCount = 6
    /// Share of the fog's opacity carried by the drifting puffs.
    private let driftingPuffShare: CGFloat = 0.4
    private var driftingPuffs: [SKSpriteNode] = []
    private var driftingPuffSpeeds: [CGFloat] = []
    private var driftingPuffAlphaFactors: [CGFloat] = []

    // The wipeable grid carries most of the density.
    private let gridSpacing: CGFloat = 100
    /// Opacity of each grid blob relative to the fog's opacity (blobs overlap, so this stays low).
    private let gridBlobShare: CGFloat = 0.45
    private var gridBlobs: [SKSpriteNode] = []
    private var gridBlobAlphaFactors: [CGFloat] = []
    /// How much fog is left in each grid cell, from 0 (wiped clear) to 1.
    private var gridDensities: [CGFloat] = []
    private var gridColumnCount = 0
    private var gridRowCount = 0

    /// Cursor wipe size, and how fast wiped patches fill back in (density per second).
    private let wipeRadius: CGFloat = 80
    private let refillRate: CGFloat = 0.05

    private var sceneSize: CGSize = .zero
    private var currentAlpha: CGFloat = 0
    /// Whether any wiped patch is still filling back in, and the fog opacity the grid was last drawn at.
    private var hasWipedPatches = false
    private var gridAlpha: CGFloat = -1
    /// Kept so a rebuilt grid gets the same tint.
    private var fogColor: NSColor?

    /// Whether any fog is showing.
    var isVisible: Bool { currentAlpha > 0.005 }

    private func preparePuffs() {
        for _ in 0..<driftingPuffCount {
            let puffSprite = SKSpriteNode(texture: WeatherTextures.fogPuff)
            containerNode.addChild(puffSprite)
            driftingPuffs.append(puffSprite)
            driftingPuffSpeeds.append(CGFloat.random(in: 8...20))
            driftingPuffAlphaFactors.append(CGFloat.random(in: 0.6...1))
        }
        containerNode.isHidden = true
    }

    /// Scatters the drifting puffs and rebuilds the grid for a new scene size.
    func layOut(sceneSize: CGSize) {
        self.sceneSize = sceneSize
        guard !driftingPuffs.isEmpty else { return }

        for puffSprite in driftingPuffs {
            puffSprite.size = CGSize(
                width: sceneSize.width * CGFloat.random(in: 0.5...0.9),
                height: sceneSize.height * CGFloat.random(in: 0.25...0.45)
            )
            puffSprite.color = fogColor ?? .white
            puffSprite.colorBlendFactor = fogColor == nil ? 0 : 1
            puffSprite.position = CGPoint(
                x: CGFloat.random(in: 0...max(sceneSize.width, 1)),
                y: CGFloat.random(in: 0...max(sceneSize.height, 1))
            )
        }

        // Rebuild the grid only when the screen size changes.
        for gridBlob in gridBlobs {
            gridBlob.removeFromParent()
        }
        gridBlobs.removeAll()
        gridBlobAlphaFactors.removeAll()
        gridDensities.removeAll()

        gridAlpha = -1
        gridColumnCount = Int((sceneSize.width / gridSpacing).rounded(.up)) + 1
        gridRowCount = Int((sceneSize.height / gridSpacing).rounded(.up)) + 1
        for row in 0..<gridRowCount {
            for column in 0..<gridColumnCount {
                let gridBlob = SKSpriteNode(texture: WeatherTextures.fogBlob)
                let blobSize = gridSpacing * 2.2 * CGFloat.random(in: 0.9...1.1)
                gridBlob.size = CGSize(width: blobSize, height: blobSize)
                // A little jitter keeps the grid from looking regular.
                gridBlob.position = CGPoint(
                    x: CGFloat(column) * gridSpacing + CGFloat.random(in: -20...20),
                    y: CGFloat(row) * gridSpacing + CGFloat.random(in: -20...20)
                )
                gridBlob.alpha = 0
                gridBlob.color = fogColor ?? .white
                gridBlob.colorBlendFactor = fogColor == nil ? 0 : 1
                containerNode.addChild(gridBlob)
                gridBlobs.append(gridBlob)
                gridBlobAlphaFactors.append(CGFloat.random(in: 0.7...1))
                gridDensities.append(1)
            }
        }
    }

    /// Fades toward `targetAlpha`, drifts the puffs with the wind, and refills wiped patches.
    func update(deltaTime: CGFloat, easing: CGFloat, targetAlpha: CGFloat, windDrift: CGFloat) {
        currentAlpha += (targetAlpha - currentAlpha) * easing
        // Finish the fade exactly instead of creeping toward it forever.
        if abs(targetAlpha - currentAlpha) < 0.0005 {
            currentAlpha = targetAlpha
        }
        containerNode.isHidden = !isVisible
        guard isVisible else {
            if targetAlpha == 0, !driftingPuffs.isEmpty {
                containerNode.removeAllChildren()
                driftingPuffs.removeAll()
                driftingPuffSpeeds.removeAll()
                driftingPuffAlphaFactors.removeAll()
                gridBlobs.removeAll()
                gridBlobAlphaFactors.removeAll()
                gridDensities.removeAll()
                gridColumnCount = 0
                gridRowCount = 0
                hasWipedPatches = false
                gridAlpha = -1
            }
            return
        }
        if driftingPuffs.isEmpty {
            preparePuffs()
            layOut(sceneSize: sceneSize)
            containerNode.isHidden = false
        }

        // Drifting puffs move with the wind and wrap around the screen edges.
        let driftDirection: CGFloat = windDrift >= 0 ? 1 : -1
        let windBoost = 1 + abs(windDrift) * 2
        for index in driftingPuffs.indices {
            let puffSprite = driftingPuffs[index]
            puffSprite.alpha = currentAlpha * driftingPuffShare * driftingPuffAlphaFactors[index]
            puffSprite.position.x += driftingPuffSpeeds[index] * driftDirection * windBoost * deltaTime

            let halfWidth = puffSprite.size.width / 2
            if puffSprite.position.x - halfWidth > sceneSize.width {
                puffSprite.position.x = -halfWidth
            } else if puffSprite.position.x + halfWidth < 0 {
                puffSprite.position.x = sceneSize.width + halfWidth
            }
        }

        // Grid blobs slowly fill back in after being wiped. Once every patch is full and the fog
        // has finished fading, nothing changes, so the grid is left alone.
        let isFading = abs(targetAlpha - currentAlpha) > 0.0005
        guard isFading || hasWipedPatches || gridAlpha != currentAlpha else { return }

        let refillAmount = refillRate * deltaTime
        var stillRefilling = false
        for index in gridBlobs.indices {
            if gridDensities[index] < 1 {
                gridDensities[index] = min(gridDensities[index] + refillAmount, 1)
                stillRefilling = stillRefilling || gridDensities[index] < 1
            }
            let blobAlpha = currentAlpha * gridBlobShare * gridDensities[index] * gridBlobAlphaFactors[index]
            // Setting the same alpha still costs work, so only changed blobs are touched.
            if abs(gridBlobs[index].alpha - blobAlpha) > 0.001 {
                gridBlobs[index].alpha = blobAlpha
            }
        }
        hasWipedPatches = stillRefilling
        gridAlpha = currentAlpha
    }

    /// Tints every fog sprite, or returns them to plain white fog when `color` is nil.
    func setColor(_ color: NSColor?) {
        for fogSprite in driftingPuffs + gridBlobs {
            fogSprite.color = color ?? .white
            fogSprite.colorBlendFactor = color == nil ? 0 : 1
        }
        fogColor = color
    }

    /// Clears fog along the cursor's path, fully in the middle and softly toward the edge of the wipe.
    func wipe(along movement: CursorMotion.Movement) {
        guard isVisible, gridColumnCount > 0 else { return }

        movement.forEachSample(spacing: 20, maximumSamples: 30) { point in
            let firstColumn = max(Int(((point.x - wipeRadius) / gridSpacing).rounded(.down)), 0)
            let lastColumn = min(Int(((point.x + wipeRadius) / gridSpacing).rounded(.up)), gridColumnCount - 1)
            let firstRow = max(Int(((point.y - wipeRadius) / gridSpacing).rounded(.down)), 0)
            let lastRow = min(Int(((point.y + wipeRadius) / gridSpacing).rounded(.up)), gridRowCount - 1)
            guard firstColumn <= lastColumn, firstRow <= lastRow else { return }

            for row in firstRow...lastRow {
                for column in firstColumn...lastColumn {
                    let cellCenter = CGPoint(x: CGFloat(column) * gridSpacing, y: CGFloat(row) * gridSpacing)
                    let distance = hypot(cellCenter.x - point.x, cellCenter.y - point.y)
                    let remainingDensity = min(max((distance - wipeRadius * 0.4) / (wipeRadius * 0.6), 0), 1)

                    let index = row * gridColumnCount + column
                    if remainingDensity < gridDensities[index] {
                        gridDensities[index] = remainingDensity
                        hasWipedPatches = true
                    }
                }
            }
        }
    }
}
