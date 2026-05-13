// Copyright 2026 Phinomenon Inc.
//
// Use of this source code is governed by an Apache license that can be
// found in the LICENSE file.

import Foundation

/// PostHog client-side configuration baked into the binary at build time.
///
/// Values come from `PostHogConfig.generated.swift`, which is produced by
/// `build-scripts/generate-posthog-config.sh` from `build-scripts/posthogConfig`.
/// When either value is empty the getter returns `nil` and the caller should
/// skip PostHog initialization.
enum PostHogEnv {
    case projectToken
    case host

    var value: String? {
        let raw: String
        switch self {
        case .projectToken: raw = PostHogGeneratedConfig.projectToken
        case .host: raw = PostHogGeneratedConfig.host
        }
        return raw.isEmpty ? nil : raw
    }
}
