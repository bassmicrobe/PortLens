import Foundation
import CoreGraphics

/// Zoom calculations use the drawing viewport, excluding toolbars and panels.
public enum DiagramZoom {
    /// Fits both dimensions with screen-space padding. Large diagrams are allowed
    /// below the manual zoom floor, so a tall setup can actually fit at launch.
    public static func fitScale(content: CGSize, viewport: CGSize, padding: CGFloat = 16) -> CGFloat {
        guard content.width.isFinite, content.height.isFinite,
              viewport.width.isFinite, viewport.height.isFinite,
              content.width > 0, content.height > 0,
              viewport.width > 0, viewport.height > 0,
              padding.isFinite, padding >= 0 else { return 1 }

        // A transient tiny viewport still produces a positive scale. Never make
        // the usable area larger than the viewport itself, even below one point.
        let width = max(viewport.width - 2 * padding, min(1, viewport.width))
        let height = max(viewport.height - 2 * padding, min(1, viewport.height))
        let scale = min(1, width / content.width, height / content.height)
        return scale.isFinite && scale > 0 ? scale : 1
    }

    /// Relative steps remain useful when auto-fit produces a small percentage.
    /// Pressing minus below 2% must not unexpectedly enlarge the diagram to 2%.
    public static func adjustedScale(current: CGFloat, direction: Int) -> CGFloat {
        guard current.isFinite, current > 0 else { return 1 }
        guard direction != 0 else { return current }
        let lowerBound = min(0.02, current)
        let proposed = direction > 0 ? current * 1.2 : current / 1.2
        return min(1.5, max(lowerBound, proposed))
    }
}
