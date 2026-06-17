// Copyright 2026 Phinomenon Inc.
//
// Use of this source code is governed by an Apache license that can be
// found in the LICENSE file.

import Cocoa
import SnapKit

protocol SearchTabsResultCellViewDelegate: AnyObject {
    func searchTabsResultCellViewDidHoverBookmarkRoot(_ cellView: SearchTabsResultCellView, item: SearchTabsItem)
}

final class SearchTabsResultCellView: NSTableCellView {
    weak var delegate: SearchTabsResultCellViewDelegate?

    private var item: SearchTabsItem?
    private var trackingArea: NSTrackingArea?

    private lazy var backgroundView: NSView = {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 8
        view.layer?.cornerCurve = .continuous
        return view
    }()

    private lazy var iconView: NSImageView = {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyDown
        imageView.contentTintColor = .secondaryLabelColor
        return imageView
    }()

    private lazy var titleLabel: NSTextField = {
        let label = SearchTabsResultCellView.makeLabel(font: .systemFont(ofSize: 13, weight: .medium))
        label.textColor = .labelColor
        label.maximumNumberOfLines = 1
        return label
    }()

    private lazy var detailLabel: NSTextField = {
        let label = SearchTabsResultCellView.makeLabel(font: .systemFont(ofSize: 12, weight: .regular))
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingMiddle
        return label
    }()

    private lazy var badgeLabel: NSTextField = {
        let label = SearchTabsResultCellView.makeLabel(font: .systemFont(ofSize: 11, weight: .medium))
        label.alignment = .center
        label.textColor = .secondaryLabelColor
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }()

    private lazy var trailingLabel: NSTextField = {
        let label = SearchTabsResultCellView.makeLabel(font: .systemFont(ofSize: 11, weight: .regular))
        label.textColor = .tertiaryLabelColor
        label.alignment = .right
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        guard let item, item.kind == .bookmarkRoot else {
            return
        }
        delegate?.searchTabsResultCellViewDidHoverBookmarkRoot(self, item: item)
    }

    func configure(with item: SearchTabsItem, selected: Bool) {
        self.item = item
        iconView.image = Self.icon(for: item)
        titleLabel.stringValue = Self.title(for: item)
        detailLabel.stringValue = Self.detail(for: item)
        detailLabel.isHidden = detailLabel.stringValue.isEmpty
        badgeLabel.stringValue = Self.badge(for: item)
        trailingLabel.stringValue = Self.trailingText(for: item)
        trailingLabel.isHidden = trailingLabel.stringValue.isEmpty
        updateSelected(selected)
    }

    func updateSelected(_ selected: Bool) {
        backgroundView.layer?.backgroundColor = selected
            ? NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
            : NSColor.clear.cgColor
    }

    private func setupViews() {
        wantsLayer = true
        addSubview(backgroundView)
        backgroundView.addSubview(iconView)
        backgroundView.addSubview(titleLabel)
        backgroundView.addSubview(detailLabel)
        backgroundView.addSubview(badgeLabel)
        backgroundView.addSubview(trailingLabel)

        backgroundView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        iconView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(12)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(18)
        }
        badgeLabel.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-12)
            make.centerY.equalToSuperview()
            make.width.greaterThanOrEqualTo(42)
        }
        trailingLabel.snp.makeConstraints { make in
            make.trailing.equalTo(badgeLabel.snp.leading).offset(-10)
            make.centerY.equalToSuperview()
            make.width.lessThanOrEqualTo(86)
        }
        titleLabel.snp.makeConstraints { make in
            make.leading.equalTo(iconView.snp.trailing).offset(9)
            make.top.equalToSuperview().offset(7)
            make.trailing.lessThanOrEqualTo(trailingLabel.snp.leading).offset(-10)
        }
        detailLabel.snp.makeConstraints { make in
            make.leading.equalTo(titleLabel)
            make.top.equalTo(titleLabel.snp.bottom).offset(1)
            make.trailing.lessThanOrEqualTo(trailingLabel.snp.leading).offset(-10)
        }
    }

    private static func makeLabel(font: NSFont) -> NSTextField {
        let label = NSTextField()
        label.isEditable = false
        label.isBordered = false
        label.drawsBackground = false
        label.font = font
        label.lineBreakMode = .byTruncatingTail
        label.cell?.truncatesLastVisibleLine = true
        label.cell?.usesSingleLineMode = true
        label.cell?.wraps = false
        return label
    }

    private static func title(for item: SearchTabsItem) -> String {
        if item.displayMode == .split, let secondary = item.secondary {
            return "\(item.primary.title) / \(secondary.title)"
        }
        return item.primary.title
    }

    private static func detail(for item: SearchTabsItem) -> String {
        if let relation = item.splitRelation {
            return NSLocalizedString(
                "Split with",
                comment: "Search Tabs - Prefix for the split partner shown in a result row"
            ) + " \(relation.partnerTitle)"
        }

        if item.displayMode == .split, let secondary = item.secondary {
            return [item.primary.url, secondary.url]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: "  •  ")
        }

        return item.primary.url ?? ""
    }

    private static func badge(for item: SearchTabsItem) -> String {
        switch item.kind {
        case .openedtab:
            return NSLocalizedString("Open", comment: "Search Tabs - Badge for an open tab result")
        case .closedtab:
            return NSLocalizedString("Closed", comment: "Search Tabs - Badge for a recently closed tab result")
        case .pin:
            return NSLocalizedString("Pinned", comment: "Search Tabs - Badge for a pinned tab result")
        case .bookmark:
            return item.state.isOpen
                ? NSLocalizedString("Open", comment: "Search Tabs - Badge for an open bookmark result")
                : NSLocalizedString("Bookmark", comment: "Search Tabs - Badge for a bookmark result")
        case .bookmarkRoot:
            return NSLocalizedString("Menu", comment: "Search Tabs - Badge for the bookmark root menu row")
        }
    }

    private static func trailingText(for item: SearchTabsItem) -> String {
        if item.state.isActive {
            return NSLocalizedString("Active", comment: "Search Tabs - Trailing label for the active tab result")
        }
        return item.state.lastActiveElapsedText ?? ""
    }

    private static func icon(for item: SearchTabsItem) -> NSImage? {
        if let data = item.primary.faviconData,
           let image = NSImage(data: data) {
            image.size = NSSize(width: 18, height: 18)
            return image
        }

        let symbolName: String
        if item.state.isSplit || item.displayMode == .split {
            symbolName = "rectangle.split.2x1"
        } else {
            switch item.kind {
            case .openedtab:
                symbolName = "rectangle.on.rectangle"
            case .closedtab:
                symbolName = "clock.arrow.circlepath"
            case .pin:
                symbolName = "pin.fill"
            case .bookmark:
                symbolName = "star.fill"
            case .bookmarkRoot:
                symbolName = "book.closed"
            }
        }
        return NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
    }
}
