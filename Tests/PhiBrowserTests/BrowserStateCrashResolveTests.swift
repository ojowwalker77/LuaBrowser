// Copyright 2026 Phinomenon Inc.
//
// Use of this source code is governed by an Apache license that can be
// found in the LICENSE file.

import XCTest
@testable import Phi

/// Locks the crash-page tab-resolution contract: `resolveTab` searches ONLY the
/// normal `tabs` table. AI Chat tabs (which live in `aiChatTabs`) must not
/// resolve — their renderer crashes are blocked at the Chromium dispatch source,
/// and the Mac client never shows a crash page for the AI chat sidebar.
@MainActor
final class BrowserStateCrashResolveTests: XCTestCase {
    private var tempDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in tempDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        tempDirectories.removeAll()
    }

    private func makeState() throws -> BrowserState {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        tempDirectories.append(directory)
        let store = LocalStore(account: Account(userID: UUID().uuidString),
                               storeDirectoryURL: directory)
        return BrowserState(windowId: 7, localStore: store, profileId: "Default")
    }

    func testResolveTabFindsNormalTabByGuid() throws {
        let state = try makeState()
        state.tabs = [
            Tab(guid: 1, url: "https://a.example", isActive: false, index: 0),
            Tab(guid: 2, url: "https://b.example", isActive: false, index: 1),
        ]
        XCTAssertEqual(state.resolveTab(2)?.guid, 2)
    }

    func testResolveTabReturnsNilForUnknownGuid() throws {
        let state = try makeState()
        state.tabs = [Tab(guid: 1, url: "https://a.example", isActive: false, index: 0)]
        XCTAssertNil(state.resolveTab(99))
    }

    func testResolveTabIgnoresAIChatTabs() throws {
        let state = try makeState()
        state.tabs = [Tab(guid: 1, url: "https://a.example", isActive: false, index: 0)]
        let aiChatTab = Tab(guid: 42,
                            url: "chrome-extension://x/chat.html",
                            isActive: false,
                            index: 0,
                            customGuid: "ai-chat-for:1")
        state.aiChatTabs["1"] = aiChatTab

        XCTAssertNil(state.resolveTab(42), "AI Chat tabs must not resolve for crash handling")
        XCTAssertEqual(state.resolveTab(1)?.guid, 1, "Normal tabs still resolve alongside an AI chat tab")
    }
}
