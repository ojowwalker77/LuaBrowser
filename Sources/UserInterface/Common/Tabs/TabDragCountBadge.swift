// Copyright 2026 Phinomenon Inc.
//
// Use of this source code is governed by an Apache license that can be
// found in the LICENSE file.

import AppKit

enum TabDragCountBadge {
    private static let height: CGFloat = 21
    private static let horizontalPadding: CGFloat = 10.5
    private static let font = NSFont.systemFont(ofSize: 12, weight: .bold)

    static func size(for count: Int) -> CGSize {
        let text = displayText(for: count) as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let textWidth = ceil(text.size(withAttributes: attributes).width)
        return CGSize(
            width: max(height, textWidth + horizontalPadding),
            height: height
        )
    }

    static func draw(count: Int, in rect: CGRect) {
        let drawingRect = rect.insetBy(dx: 0.5, dy: 0.5)
        guard drawingRect.width > 0, drawingRect.height > 0 else { return }

        let path = NSBezierPath(
            roundedRect: drawingRect,
            xRadius: drawingRect.height * 0.5,
            yRadius: drawingRect.height * 0.5
        )
        NSColor.systemRed.setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.35).setStroke()
        path.lineWidth = 1
        path.stroke()

        let text = displayText(for: count) as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let textSize = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(
                x: drawingRect.midX - textSize.width * 0.5,
                y: drawingRect.midY - textSize.height * 0.5 - 0.375
            ),
            withAttributes: attributes
        )
    }

    static func visibleUnitCount(tabIds: [Int], browserState: BrowserState) -> Int {
        visibleRepresentativeTabIds(tabIds: tabIds, browserState: browserState).count
    }

    static func visibleRepresentativeTabIds(tabIds: [Int], browserState: BrowserState) -> [Int] {
        let representedIds = Set(tabIds)
        var consumedIds = Set<Int>()
        var visibleIds: [Int] = []

        for tabId in tabIds {
            guard !consumedIds.contains(tabId) else { continue }
            consumedIds.insert(tabId)

            if let group = browserState.splitGroup(forTabId: tabId),
               !group.isPinned,
               let partnerId = group.partnerTabId(of: tabId),
               representedIds.contains(partnerId) {
                consumedIds.insert(partnerId)
            }

            visibleIds.append(tabId)
        }

        return visibleIds
    }

    private static func displayText(for count: Int) -> String {
        "\(max(0, count))"
    }
}

final class TabDragCountBadgeView: NSView {
    var count: Int = 0 {
        didSet {
            guard oldValue != count else { return }
            needsDisplay = true
        }
    }

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        TabDragCountBadge.draw(count: count, in: bounds)
    }
}
