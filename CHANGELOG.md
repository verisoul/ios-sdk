# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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


