// Copyright 2026 Phinomenon Inc.
//
// Use of this source code is governed by an Apache license that can be
// found in the LICENSE file.

import Foundation

struct TimeMachinePaths {
    static let defaultRootDirectoryName = "com.phibrowser.TimeMachine"
    static let catalogFilename = "catalog.json"
    static let snapshotsDirectoryName = "Snapshots"
    static let pendingDirectoryName = "Pending"
    static let emergencyDirectoryName = "Emergency"
    static let journalFilename = "restore-journal.json"
    static let sentryTraceQueueFilename = "pending-sentry-traces.json"

    let rootURL: URL
    let bundleIdentifier: String

    init(
        rootURL: URL? = nil,
        bundleIdentifier: String = Self.defaultBundleIdentifier()
    ) {
        self.rootURL = rootURL ?? Self.defaultRootURL(bundleIdentifier: bundleIdentifier)
        self.bundleIdentifier = bundleIdentifier
    }

    static func defaultRootURL(bundleIdentifier: String = Self.defaultBundleIdentifier()) -> URL {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return baseURL
            .appendingPathComponent(defaultRootDirectoryName, isDirectory: true)
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
    }

    private static func defaultBundleIdentifier() -> String {
#if TIME_MACHINE_INSTALLER
        return "com.phibrowser.Mac"
#else
        return FileSystemUtils.bundleId
#endif
    }

    var catalogURL: URL {
        rootURL.appendingPathComponent(Self.catalogFilename, isDirectory: false)
    }

    var snapshotsRootURL: URL {
        rootURL.appendingPathComponent(Self.snapshotsDirectoryName, isDirectory: true)
    }

    var pendingRootURL: URL {
        rootURL.appendingPathComponent(Self.pendingDirectoryName, isDirectory: true)
    }

    var emergencyRootURL: URL {
        rootURL.appendingPathComponent(Self.emergencyDirectoryName, isDirectory: true)
    }

    var sentryTraceQueueURL: URL {
        rootURL.appendingPathComponent(Self.sentryTraceQueueFilename, isDirectory: false)
    }

    func snapshotURL(id: UUID) -> URL {
        snapshotsRootURL.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func snapshotStagingURL(id: UUID) -> URL {
        snapshotsRootURL.appendingPathComponent("\(id.uuidString).staging", isDirectory: true)
    }

    func pendingOperationURL(id: UUID) -> URL {
        pendingRootURL.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func emergencyOperationURL(id: UUID) -> URL {
        emergencyRootURL.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func journalURL(operationID: UUID) -> URL {
        pendingOperationURL(id: operationID).appendingPathComponent(Self.journalFilename, isDirectory: false)
    }

    func relativePath(for url: URL) -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath) else {
            return path
        }
        let start = path.index(path.startIndex, offsetBy: rootPath.count)
        let relative = path[start...].trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return relative
    }

    func url(forRelativePath relativePath: String) -> URL {
        rootURL.appendingPathComponent(relativePath)
    }
}

enum TimeMachineSentinelStorage {
    static func applicationSupportURL(forBrowserBundleIdentifier bundleIdentifier: String) -> URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        .appendingPathComponent(
            expectedBundleIdentifier(forBrowserBundleIdentifier: bundleIdentifier),
            isDirectory: true
        )
    }

    static func expectedBundleIdentifier(forBrowserBundleIdentifier bundleIdentifier: String) -> String {
        let lowercased = bundleIdentifier.lowercased()
        if lowercased.contains(".canary.") || lowercased.contains("canary") {
            return "com.phibrowser.canary.Sentinel"
        }
        if lowercased.contains(".dev.") {
            return "com.phibrowser.dev.Sentinel"
        }
        return "com.phibrowser.Sentinel"
    }
}
