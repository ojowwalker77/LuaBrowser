// Copyright 2026 Phinomenon Inc.
//
// Use of this source code is governed by an Apache license that can be
// found in the LICENSE file.

import Cocoa
import Combine
import QuartzCore
import SnapKit

private final class SearchTabsContainerRootView: NSView {
    weak var controller: SearchTabsContainerViewController?

    override func mouseDown(with event: NSEvent) {
        guard let controller else {
            super.mouseDown(with: event)
            return
        }
        controller.handleBackgroundMouseDown(event)
    }
}

@MainActor
final class SearchTabsContainerViewController: NSViewController {
    private(set) var searchTabsController: SearchTabsViewController?
    private weak var parentView: EventBlockBgView?
    private weak var browserState: BrowserState?
    private var cancellables = Set<AnyCancellable>()
    private var focusingTabObserver: AnyCancellable?

    private(set) var hasShown = false

    init(browserState: BrowserState, superView: EventBlockBgView? = nil) {
        self.browserState = browserState
        self.parentView = superView
        self.searchTabsController = SearchTabsViewController(browserState: browserState)
        super.init(nibName: nil, bundle: nil)
        searchTabsController?.didRequestDismiss = { [weak self] in
            self?.hideSearchTabs()
        }
        superView?.mouseDown = { [weak self] event in
            self?.handleBackgroundMouseDown(event)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = SearchTabsContainerRootView()
        root.controller = self
        view = root
        view.wantsLayer = true
        view.postsFrameChangedNotifications = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupSearchTabsView()
        setupContentSizeObserver()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        focusingTabObserver = nil
        hasShown = false
    }

    func showSearchTabs() {
        guard let searchTabsView = searchTabsController?.view else {
            return
        }
        hasShown = true
        searchTabsView.alphaValue = 1
        searchTabsController?.refresh()
        updateSearchTabsFrame(searchTabsController?.contentSize ?? .zero)
        observeFocusingTabChange()
    }

    func hideSearchTabs() {
        focusingTabObserver = nil
        searchTabsController?.view.alphaValue = 0
        parentView?.removeFromSuperview()
        hasShown = false
    }

    fileprivate func handleBackgroundMouseDown(_ event: NSEvent) {
        guard let searchTabsView = searchTabsController?.view else {
            return
        }

        let clickPointInRoot = view.convert(event.locationInWindow, from: nil)
        guard !searchTabsView.frame.contains(clickPointInRoot) else {
            return
        }

        let locationInWindow = event.locationInWindow
        guard let window = event.window else {
            hideSearchTabs()
            return
        }

        hideSearchTabs()
        DispatchQueue.main.async { [weak window] in
            guard let window else { return }
            Self.forwardFirstClickToUnderlyingContent(
                at: locationInWindow,
                in: window,
                originalEvent: event
            )
        }
    }

    private func setupSearchTabsView() {
        guard let searchTabsView = searchTabsController?.view else {
            return
        }

        searchTabsView.wantsLayer = true
        searchTabsView.translatesAutoresizingMaskIntoConstraints = true
        searchTabsView.autoresizingMask = []
        searchTabsView.alphaValue = 0
        view.addSubview(searchTabsView)
    }

    private func setupContentSizeObserver() {
        searchTabsController?.$contentSize
            .receive(on: DispatchQueue.main)
            .sink { [weak self] size in
                self?.updateSearchTabsFrame(size)
            }
            .store(in: &cancellables)
    }

    private func observeFocusingTabChange() {
        focusingTabObserver = browserState?.$focusingTab
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.hideSearchTabs()
            }
    }

    private func updateSearchTabsFrame(_ size: NSSize) {
        guard let searchTabsView = searchTabsController?.view else {
            return
        }

        let parentBounds = view.bounds
        guard parentBounds.width > 0, parentBounds.height > 0 else {
            return
        }

        let width = min(SearchTabsViewController.panelWidth, parentBounds.width - 32)
        let height = min(size.height, parentBounds.height - 64)
        let x = max(16, (parentBounds.width - width) / 2)
        let y = max(24, parentBounds.height - height - 72)
        searchTabsView.frame = NSRect(x: x, y: y, width: width, height: height)
    }

    private static func forwardFirstClickToUnderlyingContent(
        at locationInWindow: NSPoint,
        in window: NSWindow,
        originalEvent: NSEvent
    ) {
        let timestamp = ProcessInfo.processInfo.systemUptime
        let windowNumber = window.windowNumber
        let flags = originalEvent.modifierFlags
        let clickCount = originalEvent.clickCount
        let eventNumber = originalEvent.eventNumber
        let pressureDown = originalEvent.pressure

        guard let mouseDown = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: locationInWindow,
            modifierFlags: flags,
            timestamp: timestamp,
            windowNumber: windowNumber,
            context: nil,
            eventNumber: eventNumber,
            clickCount: clickCount,
            pressure: pressureDown
        ) else { return }

        guard let mouseUp = NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: locationInWindow,
            modifierFlags: flags,
            timestamp: timestamp + 0.02,
            windowNumber: windowNumber,
            context: nil,
            eventNumber: eventNumber,
            clickCount: clickCount,
            pressure: 0
        ) else { return }

        window.sendEvent(mouseDown)
        window.sendEvent(mouseUp)
    }
}
