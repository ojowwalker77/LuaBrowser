// Copyright 2026 Phinomenon Inc.
//
// Use of this source code is governed by an Apache license that can be
// found in the LICENSE file.

import Cocoa
import Combine
import SnapKit

@MainActor
final class SearchTabsViewController: NSViewController {
    static let panelWidth: CGFloat = 680

    @Published private(set) var contentSize = NSSize(width: panelWidth, height: 56)
    var didRequestDismiss: (() -> Void)?

    private let viewModel: SearchTabsViewModel
    private let actionExecutor: SearchTabsActionExecutor
    private let bookmarkMenuPresenter: SearchTabsBookmarkMenuPresenter
    private var cancellables = Set<AnyCancellable>()

    private let baseHeight: CGFloat = 56
    private let maxVisibleResults = 8
    private var resultsHeightConstraint: Constraint?
    private var lastBookmarkRootMenuItemID: String?

    private lazy var shadow: NSShadow = {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.24)
        shadow.shadowOffset = NSSize(width: 0, height: -16)
        shadow.shadowBlurRadius = 40
        return shadow
    }()

    private lazy var backgroundContainer: NSView = {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96).cgColor
        view.layer?.cornerRadius = 14
        view.layer?.cornerCurve = .continuous
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
        view.clipsToBounds = true
        return view
    }()

    private lazy var inputContainer: NSView = {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        return view
    }()

    private lazy var searchIconView: NSImageView = {
        let imageView = NSImageView()
        imageView.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        imageView.imageScaling = .scaleProportionallyDown
        imageView.contentTintColor = .secondaryLabelColor
        return imageView
    }()

    private lazy var textField: SearchTabsTextField = {
        let field = SearchTabsTextField()
        field.delegate = self
        field.keyDelegate = self
        return field
    }()

    private lazy var separatorView: NSView = {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.6).cgColor
        return view
    }()

    private lazy var resultsView: SearchTabsResultsView = {
        let view = SearchTabsResultsView()
        view.delegate = self
        return view
    }()

    init(browserState: BrowserState) {
        self.viewModel = SearchTabsViewModel(dataController: SearchTabsDataController(browserState: browserState))
        self.actionExecutor = SearchTabsActionExecutor(browserState: browserState)
        self.bookmarkMenuPresenter = SearchTabsBookmarkMenuPresenter(browserState: browserState)
        super.init(nibName: nil, bundle: nil)
        bookmarkMenuPresenter.didOpenBookmark = { [weak self] in
            self?.didRequestDismiss?()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.wantsLayer = true
        view.shadow = shadow
        setupViews()
        setupBindings()
        refresh()
    }

    func refresh() {
        viewModel.reset()
        textField.stringValue = ""
        focusTextField()
    }

    func focusTextField() {
        view.window?.makeFirstResponder(textField)
    }

    private func setupViews() {
        view.addSubview(backgroundContainer)
        backgroundContainer.addSubview(inputContainer)
        inputContainer.addSubview(searchIconView)
        inputContainer.addSubview(textField)
        backgroundContainer.addSubview(separatorView)
        backgroundContainer.addSubview(resultsView)

        backgroundContainer.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        inputContainer.snp.makeConstraints { make in
            make.leading.trailing.top.equalToSuperview()
            make.height.equalTo(baseHeight)
            make.width.equalTo(Self.panelWidth)
        }
        searchIconView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(18)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(17)
        }
        textField.snp.makeConstraints { make in
            make.leading.equalTo(searchIconView.snp.trailing).offset(10)
            make.trailing.equalToSuperview().offset(-18)
            make.centerY.equalTo(searchIconView)
        }
        separatorView.snp.makeConstraints { make in
            make.top.equalTo(inputContainer.snp.bottom)
            make.leading.trailing.equalToSuperview().inset(18)
            make.height.equalTo(1)
        }
        resultsView.snp.makeConstraints { make in
            make.top.equalTo(inputContainer.snp.bottom)
            make.leading.trailing.equalToSuperview()
            resultsHeightConstraint = make.height.equalTo(0).constraint
        }
    }

    private func setupBindings() {
        viewModel.$snapshot
            .combineLatest(viewModel.$selectedIndex)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot, selectedIndex in
                self?.updateResults(snapshot.items, selectedIndex: selectedIndex)
            }
            .store(in: &cancellables)

        viewModel.$inputText
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                guard let self, self.textField.stringValue != text else { return }
                self.textField.stringValue = text
            }
            .store(in: &cancellables)
    }

    private func updateResults(_ items: [SearchTabsItem], selectedIndex: Int) {
        lastBookmarkRootMenuItemID = nil
        resultsView.updateItems(items, selectedIndex: selectedIndex, dataSourceChanged: true)

        let visibleCount = min(items.count, maxVisibleResults)
        let resultsHeight = visibleCount == 0
            ? 0
            : CGFloat(visibleCount) * SearchTabsResultsView.rowHeight
                + SearchTabsResultsView.topPadding
                + SearchTabsResultsView.bottomPadding
        resultsHeightConstraint?.update(offset: resultsHeight)
        separatorView.isHidden = items.isEmpty
        contentSize = NSSize(width: Self.panelWidth, height: baseHeight + resultsHeight)
    }

    private func execute(_ item: SearchTabsItem) {
        switch item.action {
        case .showBookmarkMenuRoot:
            showBookmarkMenu(for: item, anchorView: resultsView.anchorView(for: item.id))
        default:
            if actionExecutor.perform(item.action) {
                didRequestDismiss?()
            }
        }
    }

    private func showBookmarkMenu(for item: SearchTabsItem, anchorView: NSView?) {
        guard let anchorView else {
            return
        }
        lastBookmarkRootMenuItemID = item.id
        DispatchQueue.main.async { [weak self, weak anchorView] in
            guard let self, let anchorView else { return }
            self.bookmarkMenuPresenter.showBookmarkRootMenu(relativeTo: anchorView)
        }
    }
}

extension SearchTabsViewController: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        viewModel.updateInputText(textField.stringValue)
    }
}

extension SearchTabsViewController: SearchTabsTextFieldKeyDelegate {
    func searchTabsTextFieldDidMoveDown(_ textField: SearchTabsTextField) -> Bool {
        viewModel.selectNextItem()
        return true
    }

    func searchTabsTextFieldDidMoveUp(_ textField: SearchTabsTextField) -> Bool {
        viewModel.selectPreviousItem()
        return true
    }

    func searchTabsTextFieldDidConfirm(_ textField: SearchTabsTextField) -> Bool {
        guard let selectedItem = viewModel.selectedItem else {
            return true
        }
        execute(selectedItem)
        return true
    }

    func searchTabsTextFieldDidCancel(_ textField: SearchTabsTextField) -> Bool {
        didRequestDismiss?()
        return true
    }
}

extension SearchTabsViewController: SearchTabsResultsViewDelegate {
    func searchTabsResultsView(_ resultsView: SearchTabsResultsView, didSelect item: SearchTabsItem) {
        viewModel.selectItem(at: viewModel.items.firstIndex(where: { $0.id == item.id }) ?? -1)
        execute(item)
    }

    func searchTabsResultsView(_ resultsView: SearchTabsResultsView, didHoverBookmarkRoot item: SearchTabsItem, anchorView: NSView) {
        guard lastBookmarkRootMenuItemID != item.id else {
            return
        }
        showBookmarkMenu(for: item, anchorView: anchorView)
    }
}
