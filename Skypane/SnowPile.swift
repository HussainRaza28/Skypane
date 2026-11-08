//
//  SnowPile.swift
//  Skypane
//

import AppKit
import SpriteKit

/// Snow resting on one window's top edge, stored as a heightmap of evenly spaced columns.
/// Coordinates are in the owning scene's space (bottom-left origin).
final class SnowPile {
    /// Horizontal distance between heightmap columns.
    private static let columnSpacing: CGFloat = 3.5
    /// Tallest the pile can grow.
    static let maximumHeight: CGFloat = 11
    /// Space left bare at each end so snow doesn't sit on rounded corners. Set before `reset`.
    var cornerInset: CGFloat = 10
    /// Largest height difference between neighboring columns before snow slides sideways.
    private static let maximumSlope: CGFloat = 1.2
    /// Columns at each end over which the maximum height tapers down.
    private static let taperColumnCount = 3
    /// Heights below this count as bare.
    private static let bareHeight: CGFloat = 0.05

    private(set) var windowNumber: Int
    private(set) var windowFrame: CGRect

    /// Snow height per column.
    private var heights: [CGFloat] = []
    /// Reusable copy of the heights, used while refitting to a resized window.
    private var previousHeights: [CGFloat] = []
    /// Whether each column's spot on the top edge is uncovered by windows in front.
    private var visibleColumns: [Bool] = []
    private var firstColumnX: CGFloat = 0
    private var needsRedraw = false

    /// The soft-white pile shape and its subtle shadow, drawn in the front layer.
    let fillNode = SKShapeNode()
    let shadowNode = SKShapeNode()

    /// Whether any snow is resting on this pile.
    var hasSnow: Bool {
        heights.contains { $0 > Self.bareHeight }
    }

    /// The window's top edge, where the pile rests.
    var edgeY: CGFloat { windowFrame.maxY }

    /// Horizontal extent of the pile's columns, or nil if the window is too narrow for snow.
    var columnSpan: ClosedRange<CGFloat>? {
        heights.isEmpty ? nil : firstColumnX...columnX(at: heights.count - 1)
    }

    init(windowNumber: Int, windowFrame: CGRect) {
        self.windowNumber = windowNumber
        self.windowFrame = windowFrame

        fillNode.fillColor = NSColor(calibratedRed: 0.97, green: 0.98, blue: 1.0, alpha: 1)
        fillNode.strokeColor = .clear
        fillNode.lineWidth = 0
        fillNode.isAntialiased = true
        fillNode.zPosition = 1

        // Same shape, nudged down and darkened, so the pile reads against light title bars.
        shadowNode.fillColor = NSColor(white: 0, alpha: 0.16)
        shadowNode.strokeColor = .clear
        shadowNode.lineWidth = 0
        shadowNode.isAntialiased = true
        shadowNode.position = CGPoint(x: 0, y: -1.5)
        shadowNode.zPosition = 0

        reset(windowNumber: windowNumber, windowFrame: windowFrame)
    }

    /// Empties the pile and fits its columns to a (possibly different) window.
    func reset(windowNumber: Int, windowFrame: CGRect) {
        self.windowNumber = windowNumber
        self.windowFrame = windowFrame

        let usableWidth = windowFrame.width - cornerInset * 2
        let columnCount = usableWidth > 0 ? Int(usableWidth / Self.columnSpacing) + 1 : 0
        firstColumnX = windowFrame.minX + cornerInset

        heights.removeAll(keepingCapacity: true)
        heights.append(contentsOf: repeatElement(0, count: columnCount))
        visibleColumns.removeAll(keepingCapacity: true)
        visibleColumns.append(contentsOf: repeatElement(false, count: columnCount))
        needsRedraw = true
    }

    /// Follows the window to a new frame. If it was resized and its top edge stayed put, snow on the
    /// unchanged part of the edge stays and only snow past the new ends falls. Any other change
    /// (moving, or dragging the top edge) drops all the snow. Fallen snow goes to `shedSnow` as (x, height).
    func refit(to newFrame: CGRect, shedSnow: (CGFloat, CGFloat) -> Void) {
        let tolerance: CGFloat = 0.5
        let topEdgeStayed = abs(newFrame.maxY - windowFrame.maxY) < tolerance
        let sizeChanged = abs(newFrame.width - windowFrame.width) >= tolerance
            || abs(newFrame.height - windowFrame.height) >= tolerance

        guard topEdgeStayed, sizeChanged else {
            shedAllSnow(shedSnow)
            reset(windowNumber: windowNumber, windowFrame: newFrame)
            return
        }

        // Keep a copy of the old snow, positioned by its old columns.
        let oldFirstColumnX = firstColumnX
        previousHeights.removeAll(keepingCapacity: true)
        previousHeights.append(contentsOf: heights)

        reset(windowNumber: windowNumber, windowFrame: newFrame)

        // Snow that's now past the ends of the edge falls off.
        let newSpan = columnSpan
        for oldColumn in previousHeights.indices where previousHeights[oldColumn] > Self.bareHeight {
            let oldX = oldFirstColumnX + CGFloat(oldColumn) * Self.columnSpacing
            if newSpan?.contains(oldX) != true {
                shedSnow(oldX, previousHeights[oldColumn])
            }
        }

        // Snow on the overlapping part is carried over, interpolated onto the new column grid.
        for column in heights.indices {
            let oldPosition = (columnX(at: column) - oldFirstColumnX) / Self.columnSpacing
            let lowerOldColumn = Int(oldPosition.rounded(.down))
            guard lowerOldColumn >= 0, lowerOldColumn < previousHeights.count else { continue }

            let upperOldColumn = min(lowerOldColumn + 1, previousHeights.count - 1)
            let fraction = oldPosition - CGFloat(lowerOldColumn)
            let carriedHeight = previousHeights[lowerOldColumn] * (1 - fraction)
                + previousHeights[upperOldColumn] * fraction
            heights[column] = min(carriedHeight, heightLimit(at: column))
        }
    }

    /// Lowers every column by `amount`, for melting when it's above freezing.
    func melt(by amount: CGFloat) {
        for column in heights.indices where heights[column] > 0 {
            heights[column] = max(heights[column] - amount, 0)
            needsRedraw = true
        }
    }

    // MARK: - Landing

    /// Absorbs a flake if it crossed the pile's surface from above at an uncovered column.
    func catchFlake(atX x: CGFloat, fromY previousY: CGFloat, toY currentY: CGFloat, depositAmount: CGFloat) -> Bool {
        guard let column = nearestColumn(toX: x), visibleColumns[column] else { return false }

        let surfaceY = edgeY + heights[column]
        guard previousY >= surfaceY, currentY < surfaceY else { return false }

        deposit(depositAmount, at: column)
        return true
    }

    /// Adds snow around a column, spreading some to neighbors, then lets steep spots slide.
    private func deposit(_ amount: CGFloat, at centerColumn: Int) {
        for offset in -2...2 {
            let column = centerColumn + offset
            guard heights.indices.contains(column), visibleColumns[column] else { continue }

            let share: CGFloat
            switch abs(offset) {
            case 0: share = amount
            case 1: share = amount * 0.5
            default: share = amount * 0.2
            }
            heights[column] = min(heights[column] + share, heightLimit(at: column))
        }
        settle(around: centerColumn)
        needsRedraw = true
    }

    /// Smooths the pile by moving snow from tall columns to shorter neighbors when the slope is too steep.
    private func settle(around centerColumn: Int) {
        let firstColumn = max(centerColumn - 4, 0)
        let lastColumn = min(centerColumn + 4, heights.count - 1)
        guard firstColumn < lastColumn else { return }

        for _ in 0..<2 {
            for column in firstColumn..<lastColumn {
                let neighbor = column + 1
                guard visibleColumns[column], visibleColumns[neighbor] else { continue }

                let difference = heights[column] - heights[neighbor]
                let excess = abs(difference) - Self.maximumSlope
                guard excess > 0 else { continue }

                let transfer = excess / 2
                let (higher, lower) = difference > 0 ? (column, neighbor) : (neighbor, column)
                heights[higher] -= transfer
                heights[lower] = min(heights[lower] + transfer, heightLimit(at: lower))
            }
        }
    }

    // MARK: - Visibility and shedding

    /// Updates which columns are uncovered. Snow on newly covered columns is handed to `shedSnow`
    /// as (x, height) and removed.
    func applyVisibleSegments(_ visibleSegments: [ClosedRange<CGFloat>], shedSnow: (CGFloat, CGFloat) -> Void) {
        for column in heights.indices {
            let x = columnX(at: column)
            let isVisible = visibleSegments.contains { $0.contains(x) }

            if !isVisible, heights[column] > Self.bareHeight {
                shedSnow(x, heights[column])
                heights[column] = 0
                needsRedraw = true
            }
            visibleColumns[column] = isVisible
        }
    }

    /// Whether a point is in the band where this pile's snow sits (with a little slack), for cursor brushing.
    func isInSnowBand(_ point: CGPoint) -> Bool {
        guard let columnSpan else { return false }
        return columnSpan.contains(point.x)
            && point.y >= edgeY - 4
            && point.y <= edgeY + Self.maximumHeight + 6
    }

    /// Knocks the snow within `radius` of `centerX` off the pile, handing each column to `shedSnow` as (x, height).
    func brushSnow(aroundX centerX: CGFloat, radius: CGFloat, shedSnow: (CGFloat, CGFloat) -> Void) {
        guard !heights.isEmpty else { return }

        let firstColumn = max(Int(((centerX - radius - firstColumnX) / Self.columnSpacing).rounded(.down)), 0)
        let lastColumn = min(Int(((centerX + radius - firstColumnX) / Self.columnSpacing).rounded(.up)), heights.count - 1)
        guard firstColumn <= lastColumn else { return }

        for column in firstColumn...lastColumn where heights[column] > Self.bareHeight {
            shedSnow(columnX(at: column), heights[column])
            heights[column] = 0
            needsRedraw = true
        }
    }

    /// Hands every column's snow to `shedSnow` as (x, height) and empties the pile.
    func shedAllSnow(_ shedSnow: (CGFloat, CGFloat) -> Void) {
        for column in heights.indices where heights[column] > Self.bareHeight {
            shedSnow(columnX(at: column), heights[column])
            heights[column] = 0
            needsRedraw = true
        }
    }

    // MARK: - Drawing

    /// Rebuilds the pile shape if snow changed since the last redraw.
    @discardableResult
    func redrawIfNeeded() -> Bool {
        guard needsRedraw else { return false }
        needsRedraw = false

        let pilePath = makePilePath()
        fillNode.path = pilePath
        shadowNode.path = pilePath
        return true
    }

    /// Builds a smooth outline for each run of snowy columns, using curves through column midpoints.
    private func makePilePath() -> CGPath {
        let pilePath = CGMutablePath()
        var column = 0

        while column < heights.count {
            guard heights[column] > Self.bareHeight else {
                column += 1
                continue
            }

            // Include one bare column on each side so the run tapers to the edge.
            let runStart = max(column - 1, 0)
            var runEnd = column
            while runEnd + 1 < heights.count, heights[runEnd + 1] > Self.bareHeight {
                runEnd += 1
            }
            runEnd = min(runEnd + 1, heights.count - 1)

            addRun(from: runStart, to: runEnd, to: pilePath)
            column = runEnd + 1
        }
        return pilePath
    }

    private func addRun(from startColumn: Int, to endColumn: Int, to path: CGMutablePath) {
        path.move(to: CGPoint(x: columnX(at: startColumn), y: edgeY))
        path.addLine(to: surfacePoint(at: startColumn))

        if endColumn > startColumn {
            for column in (startColumn + 1)...endColumn {
                let previousPoint = surfacePoint(at: column - 1)
                let currentPoint = surfacePoint(at: column)
                let midpoint = CGPoint(x: (previousPoint.x + currentPoint.x) / 2,
                                       y: (previousPoint.y + currentPoint.y) / 2)
                path.addQuadCurve(to: midpoint, control: previousPoint)
            }
        }

        path.addLine(to: surfacePoint(at: endColumn))
        path.addLine(to: CGPoint(x: columnX(at: endColumn), y: edgeY))
        path.closeSubpath()
    }

    // MARK: - Column helpers

    private func columnX(at column: Int) -> CGFloat {
        firstColumnX + CGFloat(column) * Self.columnSpacing
    }

    private func surfacePoint(at column: Int) -> CGPoint {
        CGPoint(x: columnX(at: column), y: edgeY + heights[column])
    }

    private func nearestColumn(toX x: CGFloat) -> Int? {
        guard !heights.isEmpty else { return nil }
        let column = Int(((x - firstColumnX) / Self.columnSpacing).rounded())
        return heights.indices.contains(column) ? column : nil
    }

    /// Maximum height for a column, lower near the ends so the pile rounds off.
    private func heightLimit(at column: Int) -> CGFloat {
        let distanceFromEnd = min(column, heights.count - 1 - column)
        let taper = min(1, CGFloat(distanceFromEnd + 1) / CGFloat(Self.taperColumnCount + 1))
        return Self.maximumHeight * taper
    }
}
