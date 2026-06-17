// Copyright 2026 Phinomenon Inc.
//
// Use of this source code is governed by an Apache license that can be
// found in the LICENSE file.

import Cocoa
import SnapKit

protocol SearchTabsResultsViewDelegate: AnyObject {
    func searchTabsResultsView(_ resultsView: SearchTabsResultsView, didSelect item: SearchTabsItem)
    func searchTabsResultsView(_ resultsView: SearchTabsResultsView, didHoverBookmarkRoot item: SearchTabsItem, anchorView: NSView)
}

final class SearchTabsResultsView: NSView {
    static let topPadding: CGFloat = 3
    static let bottomPadding: CGFloat = 5
    static let rowHeight: CGFloat = 48

    weak var delegate: SearchTabsResultsViewDelegate?

    private var items: [SearchTabsItem] = []
    private var selectedIndex: Int = -1
    private var isProgrammaticSelection = false

    private lazy var scrollView: NSScrollView = {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.backgroundColor = .clear
        scrollView.drawsBackground = false
        return scrollView
    }()

    private lazy var tableView: NSTableView = {
        let table = NSTableView()
        table.headerView = nil
        table.intercellSpacing = .zero
        table.selectionHighlightStyle = .none
        table.backgroundColor = .clear
        table.gridStyleMask = []
        table.allowsEmptySelection = true
        table.allowsMultipleSelection = false
        table.rowSizeStyle = .custom
        table.style = .fullWidth
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(handleRowClick(_:))

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("searchTabsResult"))
        column.width = 100
        table.addTableColumn(column)
        return table
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateItems(_ items: [SearchTabsItem], selectedIndex: Int, dataSourceChanged: Bool) {
        self.items = items
        updateSelection(selectedIndex, dataSourceChanged: dataSourceChanged)
    }

    func anchorView(for itemID: String) -> NSView? {
        guard let row = items.firstIndex(where: { $0.id == itemID }) else {
            return nil
        }
        return tableView.view(atColumn: 0, row: row, makeIfNecessary: false)
            ?? tableView.rowView(atRow: row, makeIfNecessary: false)
    }

    private func setupViews() {
        wantsLayer = true
        addSubview(scrollView)
        scrollView.documentView = tableView
        scrollView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.top.equalToSuperview().offset(Self.topPadding)
            make.bottom.equalToSuperview().offset(-Self.bottomPadding)
        }
    }

    private func updateSelection(_ index: Int, dataSourceChanged: Bool) {
        let oldSelection = selectedIndex
        selectedIndex = index

        if dataSourceChanged {
            tableView.reloadData()
        }

        guard selectedIndex >= 0, selectedIndex < items.count else {
            tableView.deselectAll(nil)
            return
        }

        isProgrammaticSelection = true
        tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
        tableView.scrollRowToVisible(selectedIndex)
        isProgrammaticSelection = false

        guard !dataSourceChanged, oldSelection != selectedIndex else {
            return
        }

        var rowsToReload = IndexSet(integer: selectedIndex)
        if oldSelection >= 0, oldSelection < items.count {
            rowsToReload.insert(oldSelection)
        }
        tableView.reloadData(forRowIndexes: rowsToReload, columnIndexes: IndexSet(integer: 0))
    }

    @objc private func handleRowClick(_ sender: Any?) {
        let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        guard row >= 0, row < items.count else {
            return
        }
        delegate?.searchTabsResultsView(self, didSelect: items[row])
    }
}

extension SearchTabsResultsView: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }
}

extension SearchTabsResultsView: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < items.count else {
            return nil
        }
        let cell = SearchTabsResultCellView()
        cell.delegate = self
        cell.configure(with: items[row], selected: row == selectedIndex)
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        InsetTableRowView(insets: .init(top: 2, left: 6, bottom: 2, right: 6))
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        Self.rowHeight
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isProgrammaticSelection else {
            return
        }
        let row = tableView.selectedRow
        guard row >= 0, row < items.count else {
            return
        }
        selectedIndex = row
    }
}

extension SearchTabsResultsView: SearchTabsResultCellViewDelegate {
    func searchTabsResultCellViewDidHoverBookmarkRoot(_ cellView: SearchTabsResultCellView, item: SearchTabsItem) {
        delegate?.searchTabsResultsView(self, didHoverBookmarkRoot: item, anchorView: cellView)
    }
}
