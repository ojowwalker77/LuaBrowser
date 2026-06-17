// Copyright 2026 Phinomenon Inc.
//
// Use of this source code is governed by an Apache license that can be
// found in the LICENSE file.

import XCTest
@testable import Phi

@MainActor
final class SearchTabsDataTests: XCTestCase {
    func testQueryMatcherRanksTitlePrefixBeforeTitleContainsAndURLContains() {
        let prefix = SearchTabsQueryMatcher.match(
            query: "git",
            primaryTitle: "GitHub",
            primaryURL: "https://example.com",
            secondaryTitle: nil,
            secondaryURL: nil
        )
        let titleContains = SearchTabsQueryMatcher.match(
            query: "hub",
            primaryTitle: "GitHub",
            primaryURL: "https://example.com",
            secondaryTitle: nil,
            secondaryURL: nil
        )
        let hostContains = SearchTabsQueryMatcher.match(
            query: "github",
            primaryTitle: "Docs",
            primaryURL: "https://github.com/features/copilot",
            secondaryTitle: nil,
            secondaryURL: nil
        )
        let pathContains = SearchTabsQueryMatcher.match(
            query: "copilot",
            primaryTitle: "Docs",
            primaryURL: "https://github.com/features/copilot",
            secondaryTitle: nil,
            secondaryURL: nil
        )

        XCTAssertGreaterThan(prefix?.score ?? 0, titleContains?.score ?? 0)
        XCTAssertGreaterThan(titleContains?.score ?? 0, hostContains?.score ?? 0)
        XCTAssertGreaterThan(hostContains?.score ?? 0, pathContains?.score ?? 0)
        XCTAssertEqual(prefix?.matchedFields, [.title])
        XCTAssertEqual(hostContains?.matchedFields, [.host])
        XCTAssertEqual(pathContains?.matchedFields, [.url])
    }

    func testQueryMatcherSearchesSecondaryPaneForNativeSplitEntries() {
        let match = SearchTabsQueryMatcher.match(
            query: "calendar",
            primaryTitle: "Mail",
            primaryURL: "https://mail.example",
            secondaryTitle: "Calendar",
            secondaryURL: "https://calendar.example"
        )

        XCTAssertEqual(match?.score, SearchTabsQueryMatcher.titlePrefixScore)
        XCTAssertEqual(match?.matchedFields, [.secondaryTitle])
    }

    func testQueryMatcherReturnsNilForNonMatchingQuery() {
        let match = SearchTabsQueryMatcher.match(
            query: "figma",
            primaryTitle: "Mail",
            primaryURL: "https://mail.example",
            secondaryTitle: nil,
            secondaryURL: nil
        )

        XCTAssertNil(match)
    }

    func testChromiumProviderParsesValidOpenAndRecentlyClosedTabs() {
        let snapshot = SearchTabsChromiumProvider.parse(data: [
            "openTabs": [
                [
                    "tabId": NSNumber(value: 101),
                    "windowId": "42",
                    "index": NSNumber(value: 3),
                    "title": "Phi Browser",
                    "url": "https://phi.sh",
                    "groupIdHex": "ABCDEF",
                    "active": NSNumber(value: true),
                    "pinned": false,
                    "split": "true",
                    "hostWindow": "1",
                    "lastActiveElapsedMs": "2500",
                    "lastActiveElapsedText": "2 secs ago",
                ],
            ],
            "recentlyClosedTabs": [
                [
                    "sessionId": "777",
                    "sourceEntrySessionId": NSNumber(value: 700),
                    "sourceEntryType": "window",
                    "title": "Closed Docs",
                    "url": "https://docs.phi.sh",
                    "groupIdHex": "CLOSED",
                    "lastActiveTimeMs": NSNumber(value: 1_800_000),
                    "lastActiveElapsedMs": NSNumber(value: 9_000),
                    "lastActiveElapsedText": "9 secs ago",
                ],
            ],
        ])

        XCTAssertEqual(snapshot.openTabs, [
            ChromiumSearchOpenTab(
                tabId: 101,
                windowId: 42,
                index: 3,
                title: "Phi Browser",
                url: "https://phi.sh",
                groupIdHex: "ABCDEF",
                active: true,
                pinned: false,
                split: true,
                hostWindow: true,
                lastActiveElapsedMs: 2_500,
                lastActiveElapsedText: "2 secs ago"
            ),
        ])
        XCTAssertEqual(snapshot.closedTabs, [
            ChromiumSearchClosedTab(
                sessionId: 777,
                sourceEntrySessionId: 700,
                sourceEntryType: "window",
                title: "Closed Docs",
                url: "https://docs.phi.sh",
                groupIdHex: "CLOSED",
                lastActiveTimeMs: 1_800_000,
                lastActiveElapsedMs: 9_000,
                lastActiveElapsedText: "9 secs ago",
                providerOrder: 0
            ),
        ])
    }

    func testChromiumProviderSkipsMalformedItemsWithoutDroppingValidSiblings() {
        let snapshot = SearchTabsChromiumProvider.parse(data: [
            "openTabs": [
                [
                    "tabId": 0,
                    "windowId": 42,
                    "title": "Invalid Open Tab",
                ],
                "not a dictionary",
                [
                    "tabId": "202",
                    "windowId": NSNumber(value: 84),
                    "title": "Valid Open Tab",
                ],
            ],
            "recentlyClosedTabs": [
                [
                    "sessionId": -1,
                    "title": "Invalid Closed Tab",
                ],
                "not a dictionary",
                [
                    "sessionId": NSNumber(value: 303),
                    "title": "Valid Closed Tab",
                ],
            ],
        ])

        XCTAssertEqual(snapshot.openTabs, [
            ChromiumSearchOpenTab(
                tabId: 202,
                windowId: 84,
                index: 0,
                title: "Valid Open Tab",
                url: "about:blank",
                groupIdHex: "",
                active: false,
                pinned: false,
                split: false,
                hostWindow: false,
                lastActiveElapsedMs: Int64.max,
                lastActiveElapsedText: ""
            ),
        ])
        XCTAssertEqual(snapshot.closedTabs, [
            ChromiumSearchClosedTab(
                sessionId: 303,
                sourceEntrySessionId: 303,
                sourceEntryType: "unknown",
                title: "Valid Closed Tab",
                url: "",
                groupIdHex: "",
                lastActiveTimeMs: 0,
                lastActiveElapsedMs: Int64.max,
                lastActiveElapsedText: "",
                providerOrder: 2
            ),
        ])
    }

    func testChromiumProviderRejectsBooleanAndFractionalNumberIDs() {
        let snapshot = SearchTabsChromiumProvider.parse(data: [
            "openTabs": [
                [
                    "tabId": NSNumber(value: true),
                    "windowId": NSNumber(value: 42),
                    "title": "Boolean Tab ID",
                ],
                [
                    "tabId": NSNumber(value: 1.9),
                    "windowId": NSNumber(value: 42),
                    "title": "Fractional Tab ID",
                ],
                [
                    "tabId": NSNumber(value: 404),
                    "windowId": NSNumber(value: 42),
                    "title": "Valid Open Tab",
                    "active": NSNumber(value: 2),
                    "pinned": NSNumber(value: 1),
                    "split": NSNumber(value: 0),
                    "hostWindow": NSNumber(value: 1.5),
                ],
            ],
            "recentlyClosedTabs": [
                [
                    "sessionId": NSNumber(value: true),
                    "title": "Boolean Session ID",
                ],
                [
                    "sessionId": NSNumber(value: 2.2),
                    "title": "Fractional Session ID",
                ],
                [
                    "sessionId": NSNumber(value: 505),
                    "title": "Valid Closed Tab",
                ],
            ],
        ])

        XCTAssertEqual(snapshot.openTabs, [
            ChromiumSearchOpenTab(
                tabId: 404,
                windowId: 42,
                index: 0,
                title: "Valid Open Tab",
                url: "about:blank",
                groupIdHex: "",
                active: false,
                pinned: true,
                split: false,
                hostWindow: false,
                lastActiveElapsedMs: Int64.max,
                lastActiveElapsedText: ""
            ),
        ])
        XCTAssertEqual(snapshot.closedTabs, [
            ChromiumSearchClosedTab(
                sessionId: 505,
                sourceEntrySessionId: 505,
                sourceEntryType: "unknown",
                title: "Valid Closed Tab",
                url: "",
                groupIdHex: "",
                lastActiveTimeMs: 0,
                lastActiveElapsedMs: Int64.max,
                lastActiveElapsedText: "",
                providerOrder: 2
            ),
        ])
    }
}
