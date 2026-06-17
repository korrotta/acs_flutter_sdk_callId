## 0.2.8

* **Screen sharing**: Render incoming screen-share streams in the participant grid, with dedicated handling so a shared screen and camera feeds display together.
* **Multi-participant video stability**: Reworked remote video rendering to track each participant's renderer independently, preventing frozen or blank tiles when participants join, leave, or toggle their camera.
* **iOS**: Added a native exception guard around local video stream creation so the app fails gracefully instead of crashing when camera hardware is briefly unavailable.
* **Android**: Hardened the screen-share capture lifecycle handling.
* **Calling API**: Consolidated call state and event models for clearer, type-safe call handling.
* **Cleanup**: Removed the deprecated chat module and its tests (chat was retired in 0.2.3); package description and topics updated accordingly.
* **Tooling**: Upgraded to `flutter_lints` 6.0.0; static analysis passes with no issues.

## 0.2.7

* **Critical Bug Fix**: Prevent crash when ACS SDK throws NSException during `LocalVideoStream` initialization
* iOS: Add Objective-C exception catcher to safely handle `ACSLocalVideoStream init:` failures
* Android: Add try-catch around `LocalVideoStream` constructor for defensive error handling
* Gracefully returns error to Flutter instead of crashing the app
* Addresses crash on iOS 18.6+ when camera hardware is temporarily unavailable

## 0.2.6

* **Critical Bug Fix**: Fixed NullPointerException crash in media statistics serialization on both platforms
* **Android**: Fixed null-safety in `serializeOutgoingStatistics()` and `serializeIncomingStatistics()` methods
* **iOS**: Fixed null-safety in `serialize(outgoingStatistics:)` and `serialize(incomingStatistics:)` methods
* **Impact**: Prevents app crashes when joining calls with video/mic disabled or during initial connection phase
* **Details**: Added null checks to gracefully handle race condition when media statistics collection starts before streams are established
* **README**: Updated to document chat module removal (removed in v0.2.3 for app size optimization)

## 0.2.5

* **Bug Fix**: Prevent crash when camera permission is denied during video call initialization
* iOS: Add `AVCaptureDevice.authorizationStatus` check before creating `LocalVideoStream`
* Android: Add `ContextCompat.checkSelfPermission` check before creating `LocalVideoStream`
* Gracefully handle denied camera permissions instead of crashing the app

## 0.2.4

* Updated README.md with accurate documentation
* Fixed broken documentation links
* Updated Chat section with deprecation notice
* Fixed analyzer warnings in example app
* Improved dartdoc comments

## 0.2.3

* **BREAKING**: Chat SDK removed to reduce app size - `createChatClient()` now throws `UnsupportedError`
* For chat functionality, use UI Library ChatComposite or implement server-side chat
* Documentation update for UI Library features
* Updated README.md with comprehensive UI Library documentation
* Added comparison table between Custom UI and UI Library approaches
* Added UI Library usage examples (group calls, Teams meetings)
* Reorganized README structure to distinguish between two SDK approaches
* Updated architecture diagram to show both AcsFlutterSdk and AcsUiLibrary
* Added Documentation section with links to implementation guide

## 0.2.2

* Add Azure Communication Services UI Library support
* New AcsUiLibrary class for pre-built CallComposite and ChatComposite components
* Add native Android UI Library plugin (AcsUiLibraryPlugin.kt)
* Add native iOS UI Library plugin (AcsUiLibraryPlugin.swift)
* Support for Group Calls, Teams Meetings, Rooms, and 1:1 calls via UI composites
* Add localization support for 20+ languages in UI Library
* Add theming and multitasking (Picture-in-Picture) options
* Comprehensive UI Library implementation documentation
* Fix deprecated Color.value usage (now uses toARGB32)
* Remove unnecessary dart:typed_data import

## 0.1.3

* Fix Android compilation errors for Azure Chat SDK 2.0.3 API compatibility
* Update Android plugin to use correct Azure SDK method signatures
* Fix manifest merger conflicts and resource packaging issues
* Resolve Kotlin compilation errors in calling and chat modules

## 0.1.2

* Add `joinTeamsMeeting` APIs on Dart, Android, and iOS bridges
* Wire the example app with manual group call / Teams meeting join flows
* Document initialization requirements and Teams meeting limitations
* Extend unit tests to cover the new meeting-link workflow

## 0.1.1

* Fix platform channel payload mismatches for calling and chat responses
* Require chat endpoint during initialization and harden message parsing
* Update Android/iOS plugin package metadata and example app permissions
* Refresh documentation to clarify identity requirements and remove unsupported features
* Prepare build scripts and podspec for publishing under the new namespace
* Add Android video support (local preview, remote rendering, camera switching) and runtime permission helper

## 0.1.0

* Initial release of Azure Communication Services Flutter SDK
* ✅ Identity management support (create users, manage tokens)
* ✅ Voice and video calling capabilities
* ✅ Chat functionality with real-time messaging
* ✅ Android support (API 24+)
* ✅ iOS support (iOS 13.0+)
* ✅ Comprehensive documentation and examples
* ✅ Sound null safety support
* 📦 Uses Azure Communication Services SDK versions:
  * Android: Calling 2.15.0, Chat 2.0.3, Common 1.2.1
  * iOS: Calling 2.15.1, Chat 1.3.6, Common 1.3.0
