// Copyright 2026 Phinomenon Inc.
//
// Use of this source code is governed by an Apache license that can be
// found in the LICENSE file.

import Foundation

struct MemoryUsageThresholdPolicy {
    static let minimumThresholdBytes: UInt64 = 4 * 1024 * 1024 * 1024
    static let maximumThresholdBytes: UInt64 = 12 * 1024 * 1024 * 1024

    static func defaultThresholdBytes(physicalMemoryBytes: UInt64) -> UInt64 {
        min(max(minimumThresholdBytes, physicalMemoryBytes / 2), maximumThresholdBytes)
    }
}

struct ProcessMemoryInfo: Equatable {
    let pid: pid_t
    let ppid: pid_t
    let name: String
    let path: String?
    let residentBytes: UInt64

    var sentryContext: [String: Any] {
        var context: [String: Any] = [
            "pid": Int(pid),
            "ppid": Int(ppid),
            "name": name,
            "residentBytes": residentBytes,
            "residentGB": Double(residentBytes) / Double(1024 * 1024 * 1024)
        ]

        if let path {
            context["path"] = path
        }

        return context
    }
}

struct MemoryUsageSnapshot: Equatable {
    let capturedAt: Date
    let rootPid: pid_t
    let physicalMemoryBytes: UInt64
    let thresholdBytes: UInt64
    let processes: [ProcessMemoryInfo]
    let topProcesses: [ProcessMemoryInfo]

    init(
        capturedAt: Date,
        rootPid: pid_t,
        physicalMemoryBytes: UInt64,
        thresholdBytes: UInt64,
        processes: [ProcessMemoryInfo],
        topProcessLimit: Int = 10
    ) {
        self.capturedAt = capturedAt
        self.rootPid = rootPid
        self.physicalMemoryBytes = physicalMemoryBytes
        self.thresholdBytes = thresholdBytes
        self.processes = processes
        self.topProcesses = Array(
            processes
                .sorted { $0.residentBytes > $1.residentBytes }
                .prefix(max(0, topProcessLimit))
        )
    }

    var totalResidentBytes: UInt64 {
        processes.reduce(0) { $0 + $1.residentBytes }
    }

    var processCount: Int {
        processes.count
    }

    var exceedsThreshold: Bool {
        totalResidentBytes > thresholdBytes
    }

    var sentryContext: [String: Any] {
        [
            "capturedAt": ISO8601DateFormatter().string(from: capturedAt),
            "rootPid": Int(rootPid),
            "physicalMemoryBytes": physicalMemoryBytes,
            "physicalMemoryGB": Double(physicalMemoryBytes) / Double(1024 * 1024 * 1024),
            "thresholdBytes": thresholdBytes,
            "thresholdGB": Double(thresholdBytes) / Double(1024 * 1024 * 1024),
            "totalResidentBytes": totalResidentBytes,
            "totalResidentGB": Double(totalResidentBytes) / Double(1024 * 1024 * 1024),
            "processCount": processCount,
            "exceedsThreshold": exceedsThreshold,
            "topProcesses": topProcesses.map(\.sentryContext)
        ]
    }
}
