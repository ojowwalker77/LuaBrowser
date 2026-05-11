// Copyright 2026 Phinomenon Inc.
//
// Use of this source code is governed by an Apache license that can be
// found in the LICENSE file.

import AppKit

/// Snapshot returned by the strip when a group drag starts. The strip
/// owns the live geometry; the controller stays geometry-agnostic.
struct TabGroupDragStartSnapshot {
    let memberTabIds: [Int]
    let sourceRange: Range<Int>
    let chipFrame: CGRect
    let sliceWidth: CGFloat
    let isCollapsed: Bool
    /// Snap candidates pre-computed at drag-start to keep them stable
    /// across the natural ↔ excluded layout transition during drag.
    let snapCandidates: [(index: Int, x: CGFloat)]
    /// Leftmost normal-zone x for pinned soft-clamping.
    let firstNormalSlotX: CGFloat
}

/// Delegate for whole-group drag. Parallel to `TabStripDragDelegate`,
/// slice-shaped.
protocol TabGroupDragDelegate: AnyObject {
    /// Build the start snapshot from the live layout. Return `nil` to
    /// veto the drag (e.g. token unknown, no live chip frame).
    func groupDragControllerSnapshot(token: String) -> TabGroupDragStartSnapshot?

    /// Requests a relayout reflecting the controller's current context.
    func groupDragControllerDidUpdate()

    /// Commits the slice move when dragging ends with a real position change.
    func groupDragControllerCommitMove(memberTabIds: [Int], to: Int)

    /// Cancels the drag and restores the original layout.
    func groupDragControllerDidCancel()

    /// Snapshot of the current `normalTabOrder`. Used by the controller
    /// for liveness checks (so a member-tab close mid-drag can abort
    /// cleanly rather than commit a stale slice).
    func groupDragControllerCurrentNormalTabOrder() -> [Int]
}

final class TabGroupDragController {
    weak var delegate: TabGroupDragDelegate?

    /// Active drag context, or `nil` when idle.
    private(set) var context: TabGroupDragContext?

    /// Whether a group drag is currently active.
    var isDragging: Bool { context != nil }

    /// Minimum horizontal mouse delta before a chip mouseDown is
    /// promoted from click-pending to active drag. Matches the chip
    /// view's internal threshold; declared here so callers can reason
    /// about the value.
    static let dragActivationThreshold: CGFloat = 4

    // MARK: - Lifecycle

    /// Capture source geometry and switch the strip into group-slice
    /// layout mode (layout-mode switching is wired in a later task).
    /// - Returns: `true` if the drag started.
    @discardableResult
    func startDragging(token: String, mouseLocation: CGPoint) -> Bool {
        guard context == nil else { return false }
        guard let snap = delegate?.groupDragControllerSnapshot(token: token) else {
            AppLogWarn("[TabGroupDrag] startDragging snapshot failed token=\(token)")
            return false
        }
        let ctx = TabGroupDragContext(
            draggingChipToken: token,
            memberTabIds: snap.memberTabIds,
            sourceRange: snap.sourceRange,
            initialMouseLocation: mouseLocation,
            initialChipFrame: snap.chipFrame,
            initialSliceWidth: snap.sliceWidth,
            isCollapsedAtDragStart: snap.isCollapsed,
            snapCandidates: snap.snapCandidates,
            firstNormalSlotX: snap.firstNormalSlotX
        )
        context = ctx
        AppLogDebug(
            "[TabGroupDrag] startDragging token=\(token) " +
            "range=\(snap.sourceRange) members=\(snap.memberTabIds) " +
            "collapsed=\(snap.isCollapsed) sliceW=\(snap.sliceWidth)"
        )
        delegate?.groupDragControllerDidUpdate()
        return true
    }

    func continueDragging(mouseLocation: CGPoint) {
        guard let ctx = context, let delegate else { return }
        // Liveness check: if any member has been closed mid-drag (the
        // tab no longer appears in normalTabOrder), abort cleanly
        // rather than commit a stale slice on mouseUp.
        if !areMembersStillLive(ctx: ctx, delegate: delegate) {
            cancelDragging()
            return
        }
        let prevTargetIndex = ctx.targetIndex
        ctx.currentMouseLocation = mouseLocation

        if !ctx.snapCandidates.isEmpty {
            // Pinned soft-clamp: proxy can visually overshoot the
            // pinned/normal boundary but the snap target stays within
            // the normal zone.
            let proxyOriginX = max(ctx.firstNormalSlotX, ctx.currentSliceOriginX)

            var bestIdx = ctx.snapCandidates[0].index
            var bestDist = abs(ctx.snapCandidates[0].x - proxyOriginX)
            for cand in ctx.snapCandidates.dropFirst() {
                let d = abs(cand.x - proxyOriginX)
                if d < bestDist {
                    bestDist = d
                    bestIdx = cand.index
                }
            }
            ctx.targetIndex = bestIdx
        }

        if ctx.targetIndex != prevTargetIndex {
            AppLogDebug(
                "[TabGroupDrag] continueDragging targetIndex=" +
                "\(prevTargetIndex)→\(ctx.targetIndex)"
            )
        }

        delegate.groupDragControllerDidUpdate()
    }

    /// - Returns: `true` if the drop committed a slice move.
    @discardableResult
    func endDragging(mouseLocation: CGPoint) -> Bool {
        guard let ctx = context else { return false }
        // Liveness check at drop time too — covers the case where a
        // member is closed between the last continueDragging and the
        // mouseUp.
        if let delegate, !areMembersStillLive(ctx: ctx, delegate: delegate) {
            cancelDragging()
            return false
        }
        ctx.currentMouseLocation = mouseLocation

        let committed: Bool
        if ctx.hasPositionChanged {
            AppLogDebug(
                "[TabGroupDrag] endDragging commit " +
                "members=\(ctx.memberTabIds) to=\(ctx.targetIndex)"
            )
            delegate?.groupDragControllerCommitMove(
                memberTabIds: ctx.memberTabIds,
                to: ctx.targetIndex
            )
            committed = true
        } else {
            AppLogDebug("[TabGroupDrag] endDragging no-op (t in source range)")
            committed = false
        }
        context = nil
        delegate?.groupDragControllerDidUpdate()
        return committed
    }

    func cancelDragging() {
        guard context != nil else { return }
        AppLogDebug("[TabGroupDrag] cancelDragging")
        context = nil
        delegate?.groupDragControllerDidCancel()
    }

    /// Returns `true` if every member in the active context is still
    /// present in the live `normalTabOrder`. Returns `false` when at
    /// least one member has been removed (e.g. tab close mid-drag).
    private func areMembersStillLive(ctx: TabGroupDragContext, delegate: TabGroupDragDelegate) -> Bool {
        let live = Set(delegate.groupDragControllerCurrentNormalTabOrder())
        for member in ctx.memberTabIds where !live.contains(member) {
            AppLogWarn(
                "[TabGroupDrag] member \(member) disappeared mid-drag " +
                "(members=\(ctx.memberTabIds)); aborting"
            )
            return false
        }
        return true
    }
}
