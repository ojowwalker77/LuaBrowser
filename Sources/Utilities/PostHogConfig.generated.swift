// Empty-default copy of the PostHog client config. Plain Xcode builds compile
// this version and run with PostHog disabled at runtime.
//
// Release builds overwrite this file with real values via
// build-scripts/generate-posthog-config.sh. That script also runs
// `git update-index --skip-worktree` on this path, so any subsequent
// regeneration stays invisible to `git status` and can't be accidentally
// committed. The flag is per-clone — the generator self-bootstraps it on
// first run, so no manual setup is required.

enum PostHogGeneratedConfig {
    static let projectToken = ""
    static let host = ""
}
