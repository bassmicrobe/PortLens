import Foundation
import CoreGraphics
import PortLensCore

public enum ZoomValidation {
    public static var cases: [CoreValidationCase] {
        [
            CoreValidationCase(name: "testZoomFitsBothViewportDimensions", run: testZoomFitsBothViewportDimensions),
            CoreValidationCase(name: "testZoomFitsCrowdedDiagramBelowOldMinimum", run: testZoomFitsCrowdedDiagramBelowOldMinimum),
            CoreValidationCase(name: "testSideBySideOverviewImprovesFittedReadability", run: testSideBySideOverviewImprovesFittedReadability),
            CoreValidationCase(name: "testZoomHandlesSmallAndInvalidGeometry", run: testZoomHandlesSmallAndInvalidGeometry),
            CoreValidationCase(name: "testZoomManualStepsStayMonotonicAfterAutoFit", run: testZoomManualStepsStayMonotonicAfterAutoFit)
        ]
    }

    public static func testZoomFitsBothViewportDimensions() throws {
        let content = CGSize(width: 1600, height: 900)
        let viewports = [CGSize(width: 640, height: 700), CGSize(width: 1400, height: 400)]
        for viewport in viewports {
            let scale = DiagramZoom.fitScale(content: content, viewport: viewport)
            try check(scale > 0 && scale <= 1, "Fit scale must be positive and must not upscale")
            try check(content.width * scale <= viewport.width - 32 + 0.001, "Width must fit with padding")
            try check(content.height * scale <= viewport.height - 32 + 0.001, "Height must fit with padding")
            let limitingMargin = min(viewport.width - 32 - content.width * scale,
                                     viewport.height - 32 - content.height * scale)
            try check(abs(limitingMargin) < 0.001, "One dimension should use the available viewport")
        }
        try check(DiagramZoom.fitScale(content: CGSize(width: 200, height: 100),
                                      viewport: CGSize(width: 1000, height: 800)) == 1,
                  "A small diagram must remain at native scale")
    }

    public static func testZoomFitsCrowdedDiagramBelowOldMinimum() throws {
        let diagram = ConnectionDiagram(roots: GraphValidation.crowdedRoots, collapsed: [])
        let viewport = CGSize(width: 640, height: 380)
        let scale = DiagramZoom.fitScale(content: diagram.size, viewport: viewport)
        try check(scale < 0.35, "Crowded fixture should exercise the previous 35% clipping bug")
        for node in diagram.nodes {
            let right = (node.center.x + ConnectionDiagram.cardWidth / 2) * scale
            let bottom = (node.center.y + ConnectionDiagram.cardHeight / 2) * scale
            try check(right <= viewport.width - 32 + 0.001 && bottom <= viewport.height - 32 + 0.001,
                      "Every card must fit, including the last Thunderbolt bus")
        }
        let larger = DiagramZoom.fitScale(content: diagram.size, viewport: CGSize(width: 1000, height: 800))
        try check(larger > scale, "A larger viewport should permit a larger fitted scale")
    }

    public static func testZoomHandlesSmallAndInvalidGeometry() throws {
        let content = CGSize(width: 1000, height: 1000)
        for viewport in [CGSize(width: 8, height: 10), CGSize(width: 0.5, height: 0.25)] {
            let scale = DiagramZoom.fitScale(content: content, viewport: viewport)
            try check(scale.isFinite && scale > 0, "A transient tiny viewport must produce a valid scale")
            try check(content.width * scale <= viewport.width && content.height * scale <= viewport.height,
                      "Minimum usable dimensions must not exceed a tiny viewport")
        }
        let invalid = [CGSize.zero, CGSize(width: -1, height: 400),
                       CGSize(width: CGFloat.infinity, height: 400), CGSize(width: 400, height: CGFloat.nan)]
        for size in invalid {
            try check(DiagramZoom.fitScale(content: size, viewport: CGSize(width: 800, height: 600)) == 1,
                      "Invalid content sizes should use a safe fallback")
            try check(DiagramZoom.fitScale(content: content, viewport: size) == 1,
                      "Invalid viewport sizes should use a safe fallback")
        }
        try check(DiagramZoom.fitScale(content: content, viewport: content, padding: -.infinity) == 1,
                  "Invalid padding should use a safe fallback")
    }

    public static func testSideBySideOverviewImprovesFittedReadability() throws {
        let roots = GraphValidation.crowdedRoots
        let collapsed = Set(roots.map(\.id))
        let overview = ConnectionDiagram(roots: roots, collapsed: collapsed)
        let individualSections = DeviceTransport.allCases.map { transport in
            ConnectionDiagram(roots: roots.filter { $0.transport == transport }, collapsed: collapsed)
        }
        let stackedSize = CGSize(width: individualSections.map { $0.size.width }.max()!,
                                 height: individualSections.reduce(0) { $0 + $1.size.height })
        let viewport = CGSize(width: 850, height: 600)
        let horizontalScale = DiagramZoom.fitScale(content: overview.size, viewport: viewport)
        let stackedScale = DiagramZoom.fitScale(content: stackedSize, viewport: viewport)
        try check(horizontalScale > stackedScale * 1.25,
                  "A wide overview must render labels substantially larger than vertically stacked transports")
        try check(overview.size.width * horizontalScale <= viewport.width - 32 + 0.001 &&
                  overview.size.height * horizontalScale <= viewport.height - 32 + 0.001,
                  "The larger overview must still fit both transport trees in the viewport")
    }

    public static func testZoomManualStepsStayMonotonicAfterAutoFit() throws {
        let scales: [CGFloat] = [0.001, 0.015, 0.02, 0.15, 0.85, 1, 1.5]
        for current in scales {
            let smaller = DiagramZoom.adjustedScale(current: current, direction: -1)
            let larger = DiagramZoom.adjustedScale(current: current, direction: 1)
            try check(smaller > 0 && smaller <= current, "Minus must never increase an auto-fitted scale")
            try check(larger >= current && larger <= 1.5, "Plus must increase or stay at the upper limit")
            try check(DiagramZoom.adjustedScale(current: current, direction: 0) == current,
                      "A zero direction must leave zoom unchanged")
        }
        try check(DiagramZoom.adjustedScale(current: .nan, direction: 1) == 1,
                  "An invalid manual input should produce a safe fallback")
    }
}

private struct ZoomValidationFailure: Error, CustomStringConvertible {
    let description: String
}

private func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw ZoomValidationFailure(description: message) }
}
