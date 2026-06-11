// Copyright 2026 Phinomenon Inc.
//
// Use of this source code is governed by an Apache license that can be
// found in the LICENSE file.

import XCTest
@testable import Phi

final class TabGroupChipMosaicFillTests: XCTestCase {

    // MARK: - Empty / sparse groups

    func test_zeroMembers_allEmpty() {
        let cells = TabGroupChipMosaicView.fillCells(memberCount: 0)
        XCTAssertEqual(cells, [.empty, .empty, .empty, .empty])
    }

    func test_oneMember_firstSlotFavicon_restEmpty() {
        let cells = TabGroupChipMosaicView.fillCells(memberCount: 1)
        XCTAssertEqual(cells, [.favicon(index: 0), .empty, .empty, .empty])
    }

    func test_twoMembers_topRowFavicons_bottomEmpty() {
        let cells = TabGroupChipMosaicView.fillCells(memberCount: 2)
        XCTAssertEqual(cells, [.favicon(index: 0), .favicon(index: 1), .empty, .empty])
    }

    func test_threeMembers_lShapeFavicons() {
        let cells = TabGroupChipMosaicView.fillCells(memberCount: 3)
        XCTAssertEqual(cells, [
            .favicon(index: 0), .favicon(index: 1),
            .favicon(index: 2), .empty
        ])
    }

    // MARK: - Full / overflow

    func test_fourMembers_allSlotsFavicon_noOverflow() {
        let cells = TabGroupChipMosaicView.fillCells(memberCount: 4)
        XCTAssertEqual(cells, [
            .favicon(index: 0), .favicon(index: 1),
            .favicon(index: 2), .favicon(index: 3)
        ])
    }

    func test_fiveMembers_threeFaviconsPlusOverflowOne() {
        let cells = TabGroupChipMosaicView.fillCells(memberCount: 5)
        XCTAssertEqual(cells, [
            .favicon(index: 0), .favicon(index: 1),
            .favicon(index: 2), .overflow(count: 2)
        ])
    }

    func test_tenMembers_overflowSeven() {
        let cells = TabGroupChipMosaicView.fillCells(memberCount: 10)
        XCTAssertEqual(cells, [
            .favicon(index: 0), .favicon(index: 1),
            .favicon(index: 2), .overflow(count: 7)
        ])
    }

    func test_largeGroup_overflowMatchesCountMinusThree() {
        let cells = TabGroupChipMosaicView.fillCells(memberCount: 103)
        XCTAssertEqual(cells, [
            .favicon(index: 0), .favicon(index: 1),
            .favicon(index: 2), .overflow(count: 100)
        ])
    }
}
