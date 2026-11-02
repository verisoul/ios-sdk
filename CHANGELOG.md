# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.74] - 2026-11-02

### Fixed
- Fixed a crash in touch and motion capture (SIGSEGV in `FraudDetection.stop()`, or "NSConcreteHashTable was mutated while being enumerated"). Capture can stop on several threads at once: after the 10th touch sample, from the 5-minute stop timer, and from `configure()` or `reinitialize()`. Since 0.4.71 these could overlap and corrupt shared state. Capture state is now guarded by one lock, and only one caller tears it down.
- `session()` no longer fails with "Data collection failed" when the collection page loads slowly. The SDK reloaded the page if it hadn't finished in 3 seconds, the reload cancelled the load still in progress, and the cancel counted as another retry, so a page that needed more than about 3 seconds failed at about 6 seconds. Each attempt now gets 8 seconds, cancellations no longer count as retries, and retries stop after 18 seconds so a failure is reported inside the 20-second `session()` timeout.

## [0.4.73] - 2026-10-19

### Changed
- The SDK collects data only while the app is in the foreground. When iOS launches the app in the background (silent push, background fetch, location), `configure()` holds collection until the app becomes active, and `session()` waits for the foreground, then collects and returns. A cached session is still returned right away. Don't await `session()` inside background handlers.
- The `session()` timeout now counts only time spent in the foreground. Before, a call made shortly before iOS suspended the app failed with "Data collection timed out" as soon as the user opened it.

### Fixed
- `session()` returns the session ID at the timeout when the device data has already been posted and App Attest is still running.
- A collection pass cut off by the app going to the background is retried once the app is in the foreground, instead of failing.
- Touch and motion capture starts once the app is in the foreground.

## [0.4.72] - 2026-10-19

### Fixed
- `session()` now recovers after a collection pass fails or times out. Before, every later `session()` call in the same app process waited 20 seconds and threw `SESSION_UNAVAILABLE` ("Session ID retrieval timed out after 20.0 seconds") until the app called `configure()` or `reinitialize()`. The next call now starts a fresh pass and keeps the same session ID while it is under 24 hours old.
- `session()` now replaces an expired (24h+) session ID inside a running app process, the way `configure()` does, instead of failing every call.

### Changed
- When a collection pass ends without native data, `session()` throws `SESSION_UNAVAILABLE` with "Data collection failed" right away instead of polling for 20 seconds. The 20-second timeout for a pass that is still running is unchanged.

## [0.4.71] - 2026-08-23

### Added
- Add `collectTouchData` to `configure()` and `setTouchCaptureEnabled(_:)` so integrators can limit touch and motion capture to flows such as signup. Capture remains enabled by default.

### Changed
- Replace the full-screen `PassthroughWindow` touch-capture view with a non-interfering gesture recognizer attached directly to the key window. The recognizer does not cancel or delay host-app touches and is removed when collection stops.

## [0.4.70] - 2026-07-07

### Fixed
- fix(fraud-detection): the touch-capture overlay cleanup used `window.viewWithTag(100)`, which searches the entire view hierarchy and could remove a host-app view that happened to carry tag 100 (React Native Fabric assigns sequential integer tags to its views). This corrupted Fabric's mounting state and crashed apps with an `NSRangeException` in `-[RCTViewComponentView unmountChildComponentView:index:]` during view teardown (e.g. app termination). The overlay is now tracked by class among the window's direct subviews and no tag is assigned.

## [0.4.69] - 2026-06-26

### Changed
- fix(session): guard the cached session against project_id/environment changes so a session minted for a different project/environment is never reused (defense-in-depth; mirrors the native Android fix)

## [0.4.68] - 2026-06-25

### Changed
- docs: update README install version references to 0.4.68
- fix(webview): build WebView URL from environment-specific host


## [0.4.67] - 2026-04-14

### Changed
- Address PR review: type-safe sanitiseForJSON, gate test hook behind #if DEBUG
- Fix NSInvalidArgumentException crash in JSON serialisation (NaN from UIKit off-main-thread reads)


## [0.4.66] - 2026-02-20

### Changed
- Add adversarial chaos tests for SDK crash resilience
- Reset singleton state in setUp to ensure unconfigured-SDK test is valid
- Fix crash when reinitialize() is called before configure()


## [0.4.65] - 2026-02-03

### Changed
- Propagate session cancellation during data collection
- Avoid rescheduling timer on empty log queue
- Avoid timer loss when log send is in flight.
- Address Bugbot cleanup in logger and session loop.
- Prevent concurrent log send loss and clean up session loop.
- Add barrier synchronization to log queue writes.
- Fix iOS reinitialize coordination and logger concurrency.


## [0.4.64] - 2026-01-08

### Changed
- chore: standarize sdk_type enum consistency
- chore: remove hardcoded SDK version and set/validate framework CFBundleShortVersionString from tag
- Add promote command to release beta versions to production


## [0.4.63] - 2025-11-26

### Changed
- feat: add --yes flag to bump-version.sh for non-interactive mode


## [0.4.63-beta.6] - 2025-11-26

### Changed
- fix: properly propagate SESSION_UNAVAILABLE error when network fails


### Fixed
- fix: properly propagate SESSION_UNAVAILABLE error when network fails
- WebView now properly signals failure instead of silently returning after retries
- Added Network Unavailable Test to Example app for manual testing

## [0.4.63-beta.5] - 2025-11-24

### Changed
- Fix: Prevent timeout exception from being swallowed in session()
- Add comprehensive tests for all three error codes
- Fix VerisoulException property conflict and improve test coverage
- chore(test): add unit test to verify SESSION_UNAVAILABLE error code is thrown on getSessionId timeout
- refactor: standarize error codes


## [0.4.63-beta.4] - 2025-11-24

### Changed
- Fix: Prevent timeout exception from being swallowed in session()
- Add comprehensive tests for all three error codes
- Fix VerisoulException property conflict and improve test coverage
- chore(test): add unit test to verify SESSION_UNAVAILABLE error code is thrown on getSessionId timeout
- refactor: standarize error codes


### Added
- Standardized error codes for consistent error handling across platforms
- New `VerisoulException` class with `errorCode` property for programmatic error identification
- New `VerisoulErrorCodes` class with constants: `SESSION_UNAVAILABLE`, `WEBVIEW_UNAVAILABLE`, `INVALID_ENVIRONMENT`
- New `VerisoulEnvironment.from(value:)` method for safe environment string parsing

### Fixed
- Fixed timeout behavior that could cause up to 40-second waits instead of the intended 20 seconds
- Timeout exceptions now propagate immediately with proper error codes

## [0.4.63-beta.3] - 2025-11-12

### Changed
- github action test


## [0.4.63-beta.2] - 2025-11-12

### Changed
- github action fixes


## [0.4.63-beta.1] - 2025-11-12

### Changed
- new make commands
- include updated xcframework bundle


## [0.4.63-beta.0] - 2025-11-12

### Changed
- fix: race condition in session creation and status checks
- refactor: replace delay toggle with parallel/sequential mode for repeat test
- fix: add session status check to prevent race condition + comprehensive test suite
- fix: add single-flight pattern & cache fast path to resolve blocking
- fix: return cached sessions immediately to prevent blocking during concurrent calls
- chore: move bump-version.sh script into scripts directory


## [0.4.62] - 2025-10-10

### Changed
- Version bump


## [0.4.61] - 2025-10-08

### Changed
- fix: include missing VerisoulSDK


## [0.4.60] - 2025-10-08

### Changed
- feat: add automated sync of XCFramework to public iOS SDK repository
- refactor: update version bump commands to use release prefix for clarity
- feat: simplify release workflow to build and publish to CocoaPods
- docs: update README.md with automated publish workflow instructions
- ci: enable CocoaPods publishing and git tag force push in release workflow


## [0.4.59] - 2025-10-07

### Changed
- ci: add CI/CD workflow (test mode)


