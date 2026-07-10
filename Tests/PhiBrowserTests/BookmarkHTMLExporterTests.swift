// Copyright 2026 Phinomenon Inc.
//
// Use of this source code is governed by an Apache license that can be
// found in the LICENSE file.

import XCTest
@testable import Phi

/// Tests for the Netscape bookmark HTML exporter: document skeleton,
/// escaping, folder nesting, split-bookmark expansion, timestamps, ICON
/// data URIs, and the default export filename. Pure serialization — the
/// menu item and NSSavePanel flow are manual E2E.
final class BookmarkHTMLExporterTests: XCTestCase {

    func testSingleBookmarkProducesNetscapeDocument() {
        let bookmark = Bookmark(guid: "g1",
                                title: "Example",
                                url: "https://example.com/",
                                createdDate: Date(timeIntervalSince1970: 1_720_000_000),
                                updatedDate: Date(timeIntervalSince1970: 1_720_000_100))

        let html = BookmarkHTMLExporter.htmlDocument(for: [bookmark])

        let expected = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <!-- This is an automatically generated file.
             It will be read and overwritten.
             DO NOT EDIT! -->
        <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
        <TITLE>Bookmarks</TITLE>
        <H1>Bookmarks</H1>
        <DL><p>
            <DT><A HREF="https://example.com/" ADD_DATE="1720000000">Example</A>
        </DL><p>

        """
        // The input carries `updatedDate` on purpose: URL entries must NOT
        // emit LAST_MODIFIED (it means "last edit" in the format, while our
        // updatedDate is also bumped by opens; Chrome's exporter omits it on
        // entries too). Folders keep it — see the nesting test.
        XCTAssertEqual(html, expected)
    }

    func testEscapesHTMLSpecialCharactersInTitleAndURL() {
        let bookmark = Bookmark(guid: "g2",
                                title: "A & B <\"quoted\"> 'single'",
                                url: "https://example.com/?a=1&b=2")

        let html = BookmarkHTMLExporter.htmlDocument(for: [bookmark])

        XCTAssertTrue(html.contains(
            "<DT><A HREF=\"https://example.com/?a=1&amp;b=2\">A &amp; B &lt;&quot;quoted&quot;&gt; &#39;single&#39;</A>"))
        XCTAssertFalse(html.contains("a=1&b=2"))
    }

    func testNestedFoldersEmitH3AndIndentedDL() {
        let inner = Bookmark(guid: "g3", title: "Inner", url: "https://inner.example/")
        let emptyFolder = Bookmark(guid: "g4", title: "Empty", isFolder: true)
        let folder = Bookmark(guid: "g5",
                              title: "Work",
                              createdDate: Date(timeIntervalSince1970: 1_720_000_000),
                              updatedDate: Date(timeIntervalSince1970: 1_720_000_100),
                              isFolder: true)
        folder.addChild(inner)
        folder.addChild(emptyFolder)

        let html = BookmarkHTMLExporter.htmlDocument(for: [folder])

        let expected = [
            "    <DT><H3 ADD_DATE=\"1720000000\" LAST_MODIFIED=\"1720000100\">Work</H3>",
            "    <DL><p>",
            "        <DT><A HREF=\"https://inner.example/\">Inner</A>",
            "        <DT><H3>Empty</H3>",
            "        <DL><p>",
            "        </DL><p>",
            "    </DL><p>",
        ].joined(separator: "\n")
        XCTAssertTrue(html.contains(expected))
    }

    func testSplitBookmarkExportsAsTwoAdjacentEntries() {
        let split = Bookmark(guid: "g6",
                             title: "Docs",
                             url: "https://left.example/",
                             secondaryUrl: "https://right.example/",
                             secondaryTitle: "Spec")
        // secondaryTitle is suppressed at creation when both panes share a
        // title — the second entry falls back to the primary title.
        let unnamedSplit = Bookmark(guid: "g7",
                                    title: "Pair",
                                    url: "https://a.example/",
                                    secondaryUrl: "https://b.example/")

        let html = BookmarkHTMLExporter.htmlDocument(for: [split, unnamedSplit])

        let expected = [
            "    <DT><A HREF=\"https://left.example/\">Docs</A>",
            "    <DT><A HREF=\"https://right.example/\">Spec</A>",
            "    <DT><A HREF=\"https://a.example/\">Pair</A>",
            "    <DT><A HREF=\"https://b.example/\">Pair</A>",
        ].joined(separator: "\n")
        XCTAssertTrue(html.contains(expected))
    }

    func testCachedFaviconEmitsIconDataURI() {
        // PNG magic bytes 0x89 0x50 0x4E 0x47 — base64 "iVBORw==".
        let bookmark = Bookmark(guid: "g8",
                                title: "Icon",
                                url: "https://icon.example/",
                                faviconData: Data([0x89, 0x50, 0x4E, 0x47]))

        let html = BookmarkHTMLExporter.htmlDocument(for: [bookmark])

        XCTAssertTrue(html.contains(
            "<DT><A HREF=\"https://icon.example/\" ICON=\"data:image/png;base64,iVBORw==\">Icon</A>"))
    }

    func testDefaultFilenameHasNoSpacesAndSanitizesSpaceName() throws {
        // Built via the current calendar so the date renders as 2026-07-10
        // in whatever timezone the test host runs in.
        let date = try XCTUnwrap(Calendar.current.date(
            from: DateComponents(year: 2026, month: 7, day: 10, hour: 12)))

        XCTAssertEqual(BookmarkHTMLExporter.defaultFilename(spaceName: "Default", date: date),
                       "Phi-Bookmarks-Default-2026-07-10.html")
        XCTAssertEqual(BookmarkHTMLExporter.defaultFilename(spaceName: "My Work: A/B", date: date),
                       "Phi-Bookmarks-My-Work-A-B-2026-07-10.html")
    }
}
