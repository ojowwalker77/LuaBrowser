// Copyright 2026 Phinomenon Inc.
//
// Use of this source code is governed by an Apache license that can be
// found in the LICENSE file.

import Combine
import Foundation

@MainActor
final class SearchTabsViewModel: ObservableObject {
    @Published private(set) var snapshot: SearchTabsSnapshot
    @Published private(set) var selectedIndex: Int = -1
    @Published private(set) var inputText: String = ""

    private let dataController: SearchTabsDataController

    var items: [SearchTabsItem] {
        snapshot.items
    }

    var selectedItem: SearchTabsItem? {
        guard selectedIndex >= 0, selectedIndex < items.count else {
            return nil
        }
        return items[selectedIndex]
    }

    init(dataController: SearchTabsDataController) {
        self.dataController = dataController
        self.snapshot = dataController.snapshot(query: "")
        self.selectedIndex = snapshot.items.isEmpty ? -1 : 0
    }

    func reset() {
        updateInputText("")
    }

    func updateInputText(_ text: String) {
        inputText = text
        snapshot = dataController.snapshot(query: text)
        selectedIndex = snapshot.items.isEmpty ? -1 : 0
    }

    func selectNextItem() {
        guard !items.isEmpty else {
            selectedIndex = -1
            return
        }
        selectedIndex = min(selectedIndex + 1, items.count - 1)
    }

    func selectPreviousItem() {
        guard !items.isEmpty else {
            selectedIndex = -1
            return
        }
        selectedIndex = max(selectedIndex - 1, 0)
    }

    func selectItem(at index: Int) {
        guard index >= 0, index < items.count else {
            return
        }
        selectedIndex = index
    }
}
