// Copyright 2026 Phinomenon Inc.
//
// Use of this source code is governed by an Apache license that can be
// found in the LICENSE file.

import Security
import XCTest
@testable import Phi

final class FeedbackOutboxArchiveTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FeedbackOutboxArchiveTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
        root = nil
        try super.tearDownWithError()
    }

    func testBucketArchiveItemsUsesOriginalByteCounts() {
        let halfBucket = UInt64(FeedbackOutbox.zipPlanningBytes / 2)
        let items = [
            archiveItem(path: "PhiLogs/a.log", plannedBytes: halfBucket),
            archiveItem(path: "PhiLogs/b.log", plannedBytes: halfBucket),
            archiveItem(path: "SentinelLogs/c.log", plannedBytes: 1)
        ]

        let buckets = FeedbackOutbox.bucketArchiveItems(items)

        XCTAssertEqual(buckets.map { $0.map(\.archivePath) }, [
            ["PhiLogs/a.log", "PhiLogs/b.log"],
            ["SentinelLogs/c.log"]
        ])
        XCTAssertTrue(buckets.allSatisfy { bucket in
            let total = bucket.reduce(Int64(0)) { $0 + Int64($1.length) }
            return total <= FeedbackOutbox.zipPlanningBytes
        })
    }

    func testCollectLogArchiveItemsSplitsOversizedLogFiles() throws {
        let logsRoot = root.appendingPathComponent("PhiLogs", isDirectory: true)
        try FileManager.default.createDirectory(at: logsRoot, withIntermediateDirectories: true)
        try Data("small".utf8).write(to: logsRoot.appendingPathComponent("small.log"))

        let largeLog = logsRoot.appendingPathComponent("large.log")
        FileManager.default.createFile(atPath: largeLog.path, contents: nil)
        let handle = try FileHandle(forWritingTo: largeLog)
        try handle.truncate(atOffset: UInt64(FeedbackOutbox.zipPlanningBytes + 1024))
        try handle.close()

        let items = try FeedbackOutbox.collectLogArchiveItems(root: logsRoot, archiveRoot: "PhiLogs")
        let largeParts = items.filter { $0.archivePath.hasPrefix("PhiLogs/large.log.part-") }

        XCTAssertEqual(largeParts.count, 2)
        XCTAssertEqual(largeParts[0].archivePath, "PhiLogs/large.log.part-1")
        XCTAssertEqual(largeParts[0].offset, 0)
        XCTAssertEqual(largeParts[0].length, UInt64(FeedbackOutbox.zipPlanningBytes))
        XCTAssertEqual(largeParts[1].archivePath, "PhiLogs/large.log.part-2")
        XCTAssertEqual(largeParts[1].offset, UInt64(FeedbackOutbox.zipPlanningBytes))
        XCTAssertEqual(largeParts[1].length, 1024)
    }

    func testSelectedAttachmentInfoAcceptsRegularFilesUnderLimit() throws {
        let fileURL = root.appendingPathComponent("note.txt")
        try Data("hello".utf8).write(to: fileURL)

        let info = try FeedbackOutbox.selectedAttachmentInfo(for: fileURL)

        XCTAssertEqual(info.size, 5)
        XCTAssertFalse(info.isImage)
        XCTAssertEqual(info.mimeType, "text/plain")
    }

    func testSelectedAttachmentInfoRejectsDirectories() throws {
        let directoryURL = root.appendingPathComponent("folder", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        XCTAssertThrowsError(try FeedbackOutbox.selectedAttachmentInfo(for: directoryURL))
    }

    func testSelectedAttachmentInfoRejectsSymlinks() throws {
        let targetURL = root.appendingPathComponent("target.txt")
        let linkURL = root.appendingPathComponent("target-link.txt")
        try Data("hello".utf8).write(to: targetURL)
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: targetURL)

        XCTAssertThrowsError(try FeedbackOutbox.selectedAttachmentInfo(for: linkURL))
    }

    func testSelectedAttachmentInfoRejectsFilesOverTenMegabytes() throws {
        let fileURL = root.appendingPathComponent("large.bin")
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: fileURL)
        try handle.truncate(atOffset: UInt64(FeedbackOutbox.maxSelectedAttachmentBytes + 1))
        try handle.close()

        XCTAssertThrowsError(try FeedbackOutbox.selectedAttachmentInfo(for: fileURL))
    }

    func testBrowserChannelNameMapsNightlyBuildToCanary() {
        XCTAssertEqual(
            FeedbackOutbox.browserChannelName(isNightlyBuild: true, isDebugBuild: false),
            "canary"
        )
    }

    func testBrowserChannelNamePrefersNightlyOverDebug() {
        XCTAssertEqual(
            FeedbackOutbox.browserChannelName(isNightlyBuild: true, isDebugBuild: true),
            "canary"
        )
    }

    func testBrowserChannelNameMapsDebugBuildToDebug() {
        XCTAssertEqual(
            FeedbackOutbox.browserChannelName(isNightlyBuild: false, isDebugBuild: true),
            "debug"
        )
    }

    func testBrowserChannelNameDefaultsToStable() {
        XCTAssertEqual(
            FeedbackOutbox.browserChannelName(isNightlyBuild: false, isDebugBuild: false),
            "stable"
        )
    }

    func testShouldDiscardFailedJobOnlyAfterFiveLargeRetries() {
        XCTAssertFalse(FeedbackOutbox.shouldDiscardFailedJob(retryCount: 5))
        XCTAssertTrue(FeedbackOutbox.shouldDiscardFailedJob(retryCount: 6))
    }

    func testMakeZipAttachmentsUsesLogsZipForSingleBucket() throws {
        let preparedDir = try makePreparedDirectory()
        let items = [
            archiveItem(path: "PhiLogs/a.log", inlineText: "phi"),
            archiveItem(path: "SentinelLogs/b.log", inlineText: "sentinel")
        ]

        let attachments = try FeedbackOutbox.makeZipAttachments(
            items: items,
            preparedDir: preparedDir,
            singleFilename: "logs.zip",
            numberedPrefix: "logs",
            attachmentType: .log,
            required: true
        )

        XCTAssertEqual(attachments.count, 1)
        XCTAssertEqual(attachments[0].filename, "logs.zip")
        XCTAssertEqual(attachments[0].mimeType, "application/zip")
        XCTAssertEqual(attachments[0].attachmentType, .log)
        XCTAssertTrue(attachments[0].required)
        XCTAssertGreaterThan(attachments[0].size, 0)
        XCTAssertLessThanOrEqual(attachments[0].size, FeedbackOutbox.maxAttachmentBytes)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(attachments[0].relativePath).path))
    }

    func testMakeZipAttachmentsPrefersSingleLogsZipWhenCompressedUnderLimit() throws {
        let preparedDir = try makePreparedDirectory()
        let items = [
            archiveItem(path: "PhiLogs/a.log", plannedBytes: UInt64(FeedbackOutbox.zipPlanningBytes)),
            archiveItem(path: "SentinelLogs/b.log", plannedBytes: 1)
        ]

        let attachments = try FeedbackOutbox.makeZipAttachments(
            items: items,
            preparedDir: preparedDir,
            singleFilename: "logs.zip",
            numberedPrefix: "logs",
            attachmentType: .log,
            required: true,
            preferSingleArchiveWhenPossible: true
        )

        XCTAssertEqual(attachments.map(\.filename), ["logs.zip"])
        XCTAssertEqual(attachments[0].attachmentType, .log)
        XCTAssertLessThanOrEqual(attachments[0].size, FeedbackOutbox.maxAttachmentBytes)
    }

    func testMakeZipAttachmentsSplitsLogsWhenSingleZipExceedsLimit() throws {
        let preparedDir = try makePreparedDirectory()
        let first = try randomData(byteCount: 11 * 1024 * 1024)
        let second = try randomData(byteCount: 11 * 1024 * 1024)
        let items = [
            ArchiveItem(
                sourceURL: nil,
                inlineData: first,
                offset: 0,
                length: UInt64(first.count),
                archivePath: "PhiLogs/random-a.log"
            ),
            ArchiveItem(
                sourceURL: nil,
                inlineData: second,
                offset: 0,
                length: UInt64(second.count),
                archivePath: "SentinelLogs/random-b.log"
            )
        ]

        let attachments = try FeedbackOutbox.makeZipAttachments(
            items: items,
            preparedDir: preparedDir,
            singleFilename: "logs.zip",
            numberedPrefix: "logs",
            attachmentType: .log,
            required: true,
            preferSingleArchiveWhenPossible: true
        )

        XCTAssertEqual(attachments.map(\.filename), ["logs-1.zip", "logs-2.zip"])
        XCTAssertTrue(attachments.allSatisfy { $0.attachmentType == .log })
        XCTAssertTrue(attachments.allSatisfy { $0.size <= FeedbackOutbox.maxAttachmentBytes })
        XCTAssertFalse(FileManager.default.fileExists(atPath: preparedDir.appendingPathComponent("logs.zip").path))
    }

    func testMakeZipAttachmentsNumbersFeedbackFilesAcrossBuckets() throws {
        let preparedDir = try makePreparedDirectory()
        let items = [
            archiveItem(path: "first.bin", plannedBytes: UInt64(FeedbackOutbox.zipPlanningBytes)),
            archiveItem(path: "second.bin", plannedBytes: 1)
        ]

        let attachments = try FeedbackOutbox.makeZipAttachments(
            items: items,
            preparedDir: preparedDir,
            singleFilename: nil,
            numberedPrefix: "feedback-files",
            attachmentType: .other,
            required: false
        )

        XCTAssertEqual(attachments.map(\.filename), ["feedback-files-1.zip", "feedback-files-2.zip"])
        XCTAssertEqual(attachments.map { $0.attachmentType.rawValue }, ["other", "other"])
        XCTAssertEqual(attachments.map(\.required), [false, false])
        XCTAssertTrue(attachments.allSatisfy { FileManager.default.fileExists(atPath: root.appendingPathComponent($0.relativePath).path) })
    }

    func testOptionalZipOverLimitIsSkippedAfterActualZipSizeCheck() throws {
        let preparedDir = try makePreparedDirectory()
        let data = try randomData(byteCount: Int(FeedbackOutbox.maxAttachmentBytes + 1024 * 1024))
        let item = ArchiveItem(
            sourceURL: nil,
            inlineData: data,
            offset: 0,
            length: UInt64(data.count),
            archivePath: "large-random.bin"
        )

        let attachments = try FeedbackOutbox.makeZipAttachments(
            items: [item],
            preparedDir: preparedDir,
            singleFilename: nil,
            numberedPrefix: "feedback-files",
            attachmentType: .other,
            required: false
        )

        XCTAssertTrue(attachments.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: preparedDir.appendingPathComponent("feedback-files-1.zip").path))
    }

    private func makePreparedDirectory() throws -> URL {
        let preparedDir = root.appendingPathComponent("prepared", isDirectory: true)
        try FileManager.default.createDirectory(at: preparedDir, withIntermediateDirectories: true)
        return preparedDir
    }

    private func archiveItem(path: String, plannedBytes: UInt64) -> ArchiveItem {
        ArchiveItem(
            sourceURL: nil,
            inlineData: Data("x".utf8),
            offset: 0,
            length: plannedBytes,
            archivePath: path
        )
    }

    private func archiveItem(path: String, inlineText: String) -> ArchiveItem {
        let data = Data(inlineText.utf8)
        return ArchiveItem(
            sourceURL: nil,
            inlineData: data,
            offset: 0,
            length: UInt64(data.count),
            archivePath: path
        )
    }

    private func randomData(byteCount: Int) throws -> Data {
        var data = Data(count: byteCount)
        let status = data.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, byteCount, bytes.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw NSError(domain: "FeedbackOutboxArchiveTests", code: Int(status))
        }
        return data
    }
}
