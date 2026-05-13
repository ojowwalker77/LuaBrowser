// Copyright 2026 Phinomenon Inc.
//
// Use of this source code is governed by an Apache license that can be
// found in the LICENSE file.

import AppKit

/// "Flag"-shaped chip rendered to the left of each visible group's first
/// member tab on the horizontal strip. Renders one of two modes
/// (`ChipMode.full` / `.compact`) — the mode is decided by
/// `TabStripLayoutEngine`, not by the chip itself, so chip width is
/// consistent with the engine's tab-width allocation in the same pass.
///
/// Visual structure:
///   ┌─────────────────────────────────┐
///   │ ▌ Work · 3 tabs           [3]   │  full
///   └─────────────────────────────────┘
///   ▌▒▒  (compact: 4pt bar + 16pt color swatch + 4pt right pad = 24pt)
///
/// Click + right-click + hover handling lives in a separate task; this
/// task is rendering-only.
final class TabGroupChipView: NSView {
    // MARK: - Metrics

    static let height: CGFloat = 22
    static let cornerRadius: CGFloat = 4
    static let barWidth: CGFloat = 4
    static let labelLeftPadding: CGFloat = 7
    static let labelRightPadding: CGFloat = 6  // tightened to leave room for chevron
    static let labelFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
    static let countFont = NSFont.systemFont(ofSize: 10, weight: .bold)
    static let countHorizontalPadding: CGFloat = 6
    static let countVerticalPadding: CGFloat = 1
    static let countToLabelGap: CGFloat = 6
    static let maxFullWidth: CGFloat = 180
    /// Extra slack added to the measured label width when computing
    /// the chip's overall width. NSTextField (TextKit) renders text
    /// a hair wider than `NSString.size(withAttributes:)` reports —
    /// glyph side-bearing, subpixel rounding, plus `.byTruncatingTail`
    /// being conservative about reserving space for the ellipsis.
    /// Without this slack the label gets exactly its natural width
    /// and gets aggressively truncated to "h…" even for short
    /// titles like "hello".
    static let labelSafetyMargin: CGFloat = 4
    /// Compact mode: bar + swatch + 4pt right pad.
    static let compactWidth: CGFloat = 24
    static let compactSwatchWidth: CGFloat = 16
    static let compactRightPad: CGFloat = 4

    // Chevron — collapse/expand state indicator. Shown in full mode at
    // the trailing edge (after label / count), and overlaid on the
    // color swatch in compact mode (replacing it visually) so the
    // collapsed/expanded state is visible regardless of chip width.
    static let chevronSize: CGFloat = 9
    static let chevronToContentGap: CGFloat = 4

    // MARK: - Callbacks (set by TabStrip)

    /// Called when the chip is clicked (mouseUp inside bounds, no drag,
    /// not a right-click). `TabStrip` uses this to fire
    /// `bridge.updateTabGroupCollapsed(...)`.
    var onClick: ((String) -> Void)?

    /// Called to populate the right-click menu. `TabStrip` reuses
    /// `TabGroupSidebarItem.makeContextMenu` here. Returns nil → no menu.
    var onMenuRequest: ((String) -> NSMenu?)?

    /// Fired when chip mouseDown + horizontal drag exceeds threshold —
    /// promotes click-pending to active group drag. Window coordinates
    /// of the current mouse position.
    var onDragStart: ((_ token: String, _ windowLocation: CGPoint) -> Void)?

    /// Fired on every `mouseDragged` while drag is active.
    var onDrag: ((_ token: String, _ windowLocation: CGPoint) -> Void)?

    /// Fired on `mouseUp` when the drag was active (not on a click).
    var onDragEnd: ((_ token: String, _ windowLocation: CGPoint) -> Void)?

    // MARK: - Hover state

    private var isHovered: Bool = false {
        didSet {
            guard oldValue != isHovered else { return }
            applyAppearance()
        }
    }
    private var hoverTrackingArea: NSTrackingArea?
    private var mouseDownInside: Bool = false

    // MARK: - Click vs drag state machine
    //
    // mouseDown captures `mouseDownLocation` and sets pendingAction = .click.
    // mouseDragged promotes to `.drag` once |Δx| crosses the threshold and
    // fires `onDragStart` once. Subsequent drag events fire `onDrag`.
    // mouseUp routes to `onClick` (still .click) or `onDragEnd` (.drag).

    private enum PendingChipAction {
        case idle
        case click
        case drag
    }
    private var pendingAction: PendingChipAction = .idle
    private var mouseDownLocation: CGPoint = .zero

    /// Horizontal pixel threshold to promote click → drag. Matches
    /// `TabGroupDragController.dragActivationThreshold`.
    private static let dragActivationThreshold: CGFloat = 4

    // MARK: - Data

    private(set) var token: String = ""
    private(set) var color: GroupColor = .grey
    private(set) var displayTitle: String = ""
    private(set) var memberCount: Int = 0
    private(set) var hasUserSetTitle: Bool = false
    private(set) var mode: ChipMode = .full
    private(set) var isCollapsed: Bool = false
    private(set) var memberFavicons: [Data?] = []

    // MARK: - Subviews / sublayers

    private let backgroundLayer = CALayer()
    private let barLayer = CALayer()
    private let compactSwatchLayer = CALayer()
    private let labelField: NSTextField = {
        let tf = NSTextField(labelWithString: "")
        tf.isEditable = false
        tf.isSelectable = false
        tf.isBezeled = false
        tf.drawsBackground = false
        tf.font = TabGroupChipView.labelFont
        tf.textColor = .labelColor
        tf.lineBreakMode = .byTruncatingTail
        tf.maximumNumberOfLines = 1
        tf.cell?.usesSingleLineMode = true
        return tf
    }()
    private let countField: NSTextField = {
        let tf = NSTextField(labelWithString: "")
        tf.isEditable = false
        tf.isSelectable = false
        tf.isBezeled = false
        tf.drawsBackground = false
        tf.font = TabGroupChipView.countFont
        tf.textColor = .secondaryLabelColor
        tf.alignment = .center
        return tf
    }()
    private let countBackgroundLayer = CALayer()
    private let chevronImageView: NSImageView = {
        let iv = NSImageView()
        iv.imageScaling = .scaleProportionallyDown
        iv.translatesAutoresizingMaskIntoConstraints = true
        return iv
    }()
    private let mosaicView = TabGroupChipMosaicView()

    // MARK: - Init

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerRadius = Self.cornerRadius

        layer?.addSublayer(backgroundLayer)
        layer?.addSublayer(barLayer)
        layer?.addSublayer(compactSwatchLayer)
        layer?.addSublayer(countBackgroundLayer)

        // Suppress implicit animations for layers we manage explicitly.
        backgroundLayer.actions = ["backgroundColor": NSNull(), "bounds": NSNull(), "position": NSNull()]
        barLayer.actions         = ["backgroundColor": NSNull(), "bounds": NSNull(), "position": NSNull()]
        compactSwatchLayer.actions = ["backgroundColor": NSNull(), "bounds": NSNull(), "position": NSNull()]
        countBackgroundLayer.actions = ["backgroundColor": NSNull(), "bounds": NSNull(), "position": NSNull(),
                                        "cornerRadius": NSNull()]

        addSubview(labelField)
        addSubview(countField)
        addSubview(chevronImageView)
        addSubview(mosaicView)
        mosaicView.isHidden = true

        toolTip = NSLocalizedString(
            "Click to collapse or expand group",
            comment: "Tab Groups - cursor tooltip for horizontal-strip group chip")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Configuration

    /// Pushes a new render state. Called by `TabStrip` once per layout
    /// pass; cheap (no measurement, just property assignments).
    func configure(
        token: String,
        color: GroupColor,
        displayTitle: String,
        memberCount: Int,
        hasUserSetTitle: Bool,
        mode: ChipMode,
        isCollapsed: Bool,
        memberFavicons: [Data?]
    ) {
        self.token = token
        self.color = color
        self.displayTitle = displayTitle
        self.memberCount = memberCount
        self.hasUserSetTitle = hasUserSetTitle
        self.mode = mode
        self.isCollapsed = isCollapsed
        self.memberFavicons = memberFavicons

        labelField.stringValue = displayTitle
        countField.stringValue = "\(memberCount)"
        mosaicView.configure(memberFavicons: memberFavicons, memberCount: memberCount)

        applyAppearance()
        needsLayout = true
    }

    /// Lightweight update used by `TabStrip` when a member's
    /// favicon data changes while the group is collapsed. Avoids
    /// the full configure (which would force a chip-width refresh
    /// and a strip relayout) — only the mosaic's cell contents
    /// change.
    ///
    /// Precondition: caller must have already invoked `configure(...)`
    /// with `isCollapsed: true` at least once, so `mosaicView.frame`
    /// is set by a prior `layoutFullMode()` pass. Calling this
    /// before the first collapsed layout would leave the mosaic at
    /// `.zero` until the next layout pass.
    func updateMosaic(memberFavicons: [Data?]) {
        self.memberFavicons = memberFavicons
        mosaicView.configure(memberFavicons: memberFavicons, memberCount: memberCount)
    }

    // MARK: - Appearance

    private func applyAppearance() {
        backgroundLayer.backgroundColor = (isHovered
            ? color.chipHoverTintColor
            : color.chipTintColor).cgColor
        barLayer.backgroundColor = color.nsColor.cgColor
        compactSwatchLayer.backgroundColor = color.chipCompactSwatchColor.cgColor
        countBackgroundLayer.backgroundColor = color.chipHoverTintColor.cgColor
        countBackgroundLayer.cornerRadius = (TabGroupChipView.countFont.pointSize +
                                              Self.countVerticalPadding * 2) / 2.0

        // Chevron points right when collapsed (suggests "click to
        // expand"), down when expanded (suggests "tabs are below /
        // click to collapse"). In full mode the chevron uses
        // secondaryLabelColor so it doesn't compete with the title;
        // in compact mode it uses the saturated group color so the
        // 24pt-wide chip still carries a strong color presence (it
        // replaces the swatch — see layoutCompactMode).
        let symbolName = isCollapsed ? "chevron.right" : "chevron.down"
        let config = NSImage.SymbolConfiguration(pointSize: Self.chevronSize, weight: .semibold)
        chevronImageView.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(config)
        chevronImageView.contentTintColor = (mode == .compact)
            ? color.nsColor
            : .secondaryLabelColor

        let showLabel = (mode == .full)
        let showMosaic = (mode == .full) && isCollapsed
        // Count badge only when expanded + user-named (existing
        // behavior). When the mosaic shows, the count is suppressed
        // because the mosaic carries the count via the overflow cell.
        let showCount = (mode == .full) && hasUserSetTitle && !isCollapsed
        // Compact mode: the chevron stands in for the swatch as the
        // single visible symbol next to the bar.
        let showCompactSwatch = false

        labelField.isHidden = !showLabel
        countField.isHidden = !showCount
        countBackgroundLayer.isHidden = !showCount
        compactSwatchLayer.isHidden = !showCompactSwatch
        mosaicView.isHidden = !showMosaic
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // Re-resolve programmatic colors against the new appearance.
        applyAppearance()
    }

    // MARK: - Layout

    override func layout() {
        super.layout()

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        backgroundLayer.frame = bounds
        barLayer.frame = CGRect(x: 0, y: 0, width: Self.barWidth, height: bounds.height)

        switch mode {
        case .full:
            layoutFullMode()
        case .compact:
            layoutCompactMode()
        }

        CATransaction.commit()
    }

    private func layoutFullMode() {
        let labelX = Self.barWidth + Self.labelLeftPadding
        let labelHeight = ceil(Self.labelFont.ascender - Self.labelFont.descender + Self.labelFont.leading)

        let chevronX = bounds.width - Self.labelRightPadding - Self.chevronSize
        let chevronY = (bounds.height - Self.chevronSize) / 2
        chevronImageView.frame = CGRect(x: chevronX, y: chevronY,
                                         width: Self.chevronSize, height: Self.chevronSize)

        if isCollapsed {
            // Mosaic occupies the space between label and chevron.
            let mosaicW = TabGroupChipMosaicView.mosaicSize
            let mosaicX = chevronX - Self.chevronToContentGap - mosaicW
            let mosaicY = (bounds.height - mosaicW) / 2
            mosaicView.frame = CGRect(x: mosaicX, y: mosaicY,
                                       width: mosaicW, height: mosaicW)

            let labelMaxX = mosaicX - Self.countToLabelGap
            labelField.frame = CGRect(x: labelX, y: (bounds.height - labelHeight) / 2,
                                       width: max(0, labelMaxX - labelX), height: labelHeight)
        } else if hasUserSetTitle {
            // Count badge sits between label and chevron.
            let countString = countField.stringValue as NSString
            let countTextWidth = countString.size(withAttributes: [.font: Self.countFont]).width
            let countWidth = ceil(countTextWidth) + Self.countHorizontalPadding * 2
            let countHeight = Self.countFont.pointSize + Self.countVerticalPadding * 2
            let countX = chevronX - Self.chevronToContentGap - countWidth
            let countY = (bounds.height - countHeight) / 2

            countBackgroundLayer.frame = CGRect(x: countX, y: countY, width: countWidth, height: countHeight)
            countField.frame = CGRect(x: countX, y: countY,
                                       width: countWidth, height: countHeight)

            let labelMaxX = countX - Self.countToLabelGap
            labelField.frame = CGRect(x: labelX, y: (bounds.height - labelHeight) / 2,
                                       width: max(0, labelMaxX - labelX), height: labelHeight)
        } else {
            // No badge, no mosaic — label fills up to the chevron's left edge.
            let labelMaxX = chevronX - Self.chevronToContentGap
            labelField.frame = CGRect(x: labelX, y: (bounds.height - labelHeight) / 2,
                                       width: max(0, labelMaxX - labelX), height: labelHeight)
        }
    }

    private func layoutCompactMode() {
        // Chevron centered in the swatch region (replaces the swatch
        // visually so chip width stays at compactWidth = 24pt).
        let chevronAreaX = Self.barWidth
        let chevronX = chevronAreaX + (Self.compactSwatchWidth - Self.chevronSize) / 2
        let chevronY = (bounds.height - Self.chevronSize) / 2
        chevronImageView.frame = CGRect(x: chevronX, y: chevronY,
                                         width: Self.chevronSize, height: Self.chevronSize)
        // labelField / countField hidden via applyAppearance().
    }

    // MARK: - Width measurement

    /// Pure measurement helper. Called by `TabStrip.refreshChipWidth(for:)`
    /// once per chip when the title / color / member count / collapsed
    /// flag changes; the result is cached in `TabStrip.chipFullWidths`
    /// and fed to the layout engine via `TabStripLayoutInput.chipFullWidths`.
    ///
    /// - Parameters:
    ///   - title: rendered group title (`group.displayTitle(memberCount:)`).
    ///   - hasUserSetTitle: drives count-badge visibility in expanded state.
    ///     Ignored when `isCollapsed` is true — the mosaic always wins over
    ///     both the badge and the bare-label paths.
    ///   - memberCount: drives count-badge digit width in expanded state.
    ///   - isCollapsed: when true, reserves mosaic (`TabGroupChipMosaicView.mosaicSize`)
    ///     in place of the count badge — even for unnamed groups, since
    ///     the mosaic is the preview signal.
    static func fullModeWidth(forTitle title: String,
                              hasUserSetTitle: Bool,
                              memberCount: Int,
                              isCollapsed: Bool) -> CGFloat {
        let labelWidth = (title as NSString)
            .size(withAttributes: [.font: labelFont])
            .width
        let chevronOverhead = chevronToContentGap + chevronSize + labelRightPadding
        var width = barWidth + labelLeftPadding
                  + ceil(labelWidth) + labelSafetyMargin
                  + chevronOverhead

        if isCollapsed {
            // Mosaic always reserves space when collapsed,
            // independent of hasUserSetTitle.
            width += countToLabelGap + TabGroupChipMosaicView.mosaicSize
        } else if hasUserSetTitle {
            let countString = "\(memberCount)" as NSString
            let countTextWidth = countString
                .size(withAttributes: [.font: countFont])
                .width
            let countWidth = ceil(countTextWidth) + countHorizontalPadding * 2
            width += countToLabelGap + countWidth
        }

        return min(width, maxFullWidth)
    }

    // MARK: - Mouse handling

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = hoverTrackingArea {
            removeTrackingArea(area)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect, .cursorUpdate],
            owner: self
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    /// Prevent AppKit from treating chip-area mouseDown as a
    /// window-drag handle. The main window has
    /// `isMovableByWindowBackground = true`
    /// (`MainBrowserWindowController.swift`), so without these two
    /// overrides drags on the chip would move the host window.
    /// `acceptsFirstResponder = true` matches `TabItemView` and is
    /// required for AppKit to treat this view as one that "responds
    /// to mouse events" — otherwise the `mouseDownCanMoveWindow`
    /// false return is ignored in the window-drag heuristic.
    override var mouseDownCanMoveWindow: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDownInside = true
        mouseDownLocation = event.locationInWindow
        pendingAction = .click
    }

    override func mouseDragged(with event: NSEvent) {
        guard mouseDownInside else { return }
        let dx = event.locationInWindow.x - mouseDownLocation.x
        switch pendingAction {
        case .click:
            if abs(dx) >= Self.dragActivationThreshold {
                pendingAction = .drag
                onDragStart?(token, event.locationInWindow)
            }
        case .drag:
            onDrag?(token, event.locationInWindow)
        case .idle:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownInside = false
            pendingAction = .idle
        }
        guard mouseDownInside else { return }
        switch pendingAction {
        case .click:
            let p = convert(event.locationInWindow, from: nil)
            guard bounds.contains(p) else { return }
            onClick?(token)
        case .drag:
            onDragEnd?(token, event.locationInWindow)
        case .idle:
            break
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        return onMenuRequest?(token)
    }

    // MARK: - Accessibility

    override func accessibilityLabel() -> String? {
        let format = isCollapsed
            ? NSLocalizedString(
                "%@ tab group, %d tabs, collapsed",
                comment: "Tab Groups - VoiceOver label for collapsed horizontal-strip group chip")
            : NSLocalizedString(
                "%@ tab group, %d tabs, expanded",
                comment: "Tab Groups - VoiceOver label for expanded horizontal-strip group chip")
        return String(format: format, color.localizedName, memberCount)
    }

    override func accessibilityRole() -> NSAccessibility.Role? { .button }
}
