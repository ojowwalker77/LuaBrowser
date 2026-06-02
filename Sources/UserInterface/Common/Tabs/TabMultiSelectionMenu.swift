// Copyright 2026 Phinomenon Inc.
//
// Use of this source code is governed by an Apache license that can be
// found in the LICENSE file.

import AppKit

enum TabMultiSelectionMenu {
    /// Populates `menu` with batch actions when a multi-selection is active.
    /// Returns true if it took over the menu; callers must then skip the single-tab menu.
    @MainActor
    static func populateIfNeeded(_ menu: NSMenu, browserState: BrowserState) -> Bool {
        guard browserState.multiSelection.isActive else { return false }
        menu.removeAllItems()

        let controller = TabMultiSelectionMenuController(browserState: browserState)
        var items: [NSMenuItem] = []

        let duplicateItem = NSMenuItem(
            title: NSLocalizedString(
                "Duplicate Tabs",
                comment: "Tab multi-selection context menu - duplicate all selected tabs"),
            action: #selector(TabMultiSelectionMenuController.duplicateSelected),
            keyEquivalent: "")
        items.append(duplicateItem)

        let copyLinksItem = NSMenuItem(
            title: NSLocalizedString(
                "Copy Links",
                comment: "Tab multi-selection context menu - copy links of all selected tabs"),
            action: #selector(TabMultiSelectionMenuController.copyLinks),
            keyEquivalent: "")
        items.append(copyLinksItem)

        items.append(.separator())

        let addToBookmarks = NSMenuItem(
            title: NSLocalizedString(
                "Add to Bookmarks",
                comment: "Tab multi-selection context menu - submenu to bookmark all selected tabs"),
            action: nil,
            keyEquivalent: "")
        let bookmarkSubmenu = NSMenu()

        let bookmarkBarItem = NSMenuItem(
            title: NSLocalizedString(
                "Bookmark Bar",
                comment: "Tab multi-selection context menu - bookmark selected tabs into the root bookmark bar"),
            action: #selector(TabMultiSelectionMenuController.addToBookmarkBar),
            keyEquivalent: "")
        bookmarkBarItem.target = controller
        bookmarkSubmenu.addItem(bookmarkBarItem)

        let folders = browserState.bookmarkManager.getAllFolderWithHierarchy()
        if !folders.isEmpty {
            buildFolderMenuItems(from: folders, into: bookmarkSubmenu, controller: controller)
        }
        bookmarkSubmenu.addItem(.separator())

        let newFolderItem = NSMenuItem(
            title: NSLocalizedString(
                "New Folder",
                comment: "Tab multi-selection context menu - bookmark selected tabs into a newly created folder"),
            action: #selector(TabMultiSelectionMenuController.createNewFolder),
            keyEquivalent: "")
        newFolderItem.target = controller
        bookmarkSubmenu.addItem(newFolderItem)

        addToBookmarks.submenu = bookmarkSubmenu
        items.append(addToBookmarks)

        items.append(.separator())

        let createGroupItem = NSMenuItem(
            title: NSLocalizedString(
                "Create Tab Group",
                comment: "Tab multi-selection context menu - create a new tab group from selected tabs"),
            action: #selector(TabMultiSelectionMenuController.createTabGroup),
            keyEquivalent: "")
        items.append(createGroupItem)

        let orderedGroups = orderedGroupsInStripOrder(state: browserState)
        if !orderedGroups.isEmpty {
            let addToGroup = NSMenuItem(
                title: NSLocalizedString(
                    "Add to Group",
                    comment: "Tab multi-selection context menu - submenu to add selected tabs to an existing tab group"),
                action: nil,
                keyEquivalent: "")
            let groupSubmenu = NSMenu()
            for group in orderedGroups {
                let memberCount = browserState.normalTabs
                    .lazy.filter { $0.groupToken == group.token }.count
                let entry = NSMenuItem(
                    title: group.displayTitle(memberCount: memberCount),
                    action: #selector(TabMultiSelectionMenuController.addToExistingGroup(_:)),
                    keyEquivalent: "")
                entry.target = controller
                entry.image = NSImage.tabGroupColorSwatch(for: group.color)
                entry.representedObject = group.token
                groupSubmenu.addItem(entry)
            }
            addToGroup.submenu = groupSubmenu
            items.append(addToGroup)
        }

        items.append(.separator())

        let closeItem = NSMenuItem(
            title: NSLocalizedString(
                "Close Tabs",
                comment: "Tab multi-selection context menu - close all selected tabs"),
            action: #selector(TabMultiSelectionMenuController.closeSelected),
            keyEquivalent: "")
        items.append(closeItem)

        items.forEach { item in
            if item.representedObject == nil {
                if item.target == nil { item.target = controller }
                item.representedObject = controller
            }
            menu.addItem(item)
        }
        return true
    }

    private static func buildFolderMenuItems(from folders: [Bookmark],
                                             into menu: NSMenu,
                                             controller: TabMultiSelectionMenuController) {
        for folder in folders {
            let folderItem = NSMenuItem(
                title: folder.title,
                action: #selector(TabMultiSelectionMenuController.addToFolder(_:)),
                keyEquivalent: "")
            folderItem.target = controller
            folderItem.representedObject = folder

            if folder.hasChildren {
                let submenu = NSMenu()
                buildFolderMenuItems(from: folder.children, into: submenu, controller: controller)
                folderItem.submenu = submenu
            }

            menu.addItem(folderItem)
        }
    }

    private static func orderedGroupsInStripOrder(state: BrowserState) -> [WebContentGroupInfo] {
        var seen = Set<String>()
        var ordered: [WebContentGroupInfo] = []
        for tab in state.normalTabs {
            guard let token = tab.groupToken,
                  !seen.contains(token),
                  let info = state.groups[token] else { continue }
            seen.insert(token)
            ordered.append(info)
        }
        return ordered
    }
}

@MainActor
final class TabMultiSelectionMenuController: NSObject {
    private weak var browserState: BrowserState?
    init(browserState: BrowserState) { self.browserState = browserState }

    @objc func duplicateSelected() { browserState?.duplicateMultiSelectedTabs() }
    @objc func copyLinks() { browserState?.copyLinksOfMultiSelectedTabs() }
    @objc func closeSelected() { browserState?.closeMultiSelectedTabs() }
    @objc func addToBookmarkBar() { browserState?.bookmarkMultiSelectedTabs(into: nil) }
    @objc func addToFolder(_ sender: NSMenuItem) {
        guard let folder = sender.representedObject as? Bookmark else { return }
        browserState?.bookmarkMultiSelectedTabs(into: folder)
    }
    @objc func createNewFolder() {
        guard let browserState,
              let window = MainBrowserWindowControllersManager.shared.activeWindowController?.window else { return }
        // Snapshot the selection now; the modal dialog clears it before the
        // completion handler runs.
        let tabs = browserState.orderedMultiSelectedTabs
        EditPinnedTabPresenter.presentModal(mode: .newFolder, from: window) { result in
            guard let name = result.title, !name.isEmpty else { return }
            browserState.bookmarkTabs(tabs, intoNewFolderNamed: name)
        }
    }
    @objc func createTabGroup() { browserState?.groupMultiSelectedTabs() }
    @objc func addToExistingGroup(_ sender: NSMenuItem) {
        guard let token = sender.representedObject as? String else { return }
        browserState?.addMultiSelectedTabs(toGroup: token)
    }

    // Disable a group entry when every selected tab is already in that group.
    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem.action == #selector(addToExistingGroup(_:)),
              let token = menuItem.representedObject as? String,
              let browserState else {
            return true
        }
        return !browserState.multiSelectionTargets(forAddingToGroup: token).isEmpty
    }
}
