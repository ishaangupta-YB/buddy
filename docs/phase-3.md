# Phase 3 — macOS menu bar app

## Constraints

- Menu-bar-only (`LSUIElement`), accessory activation policy, no dock icon or main window.
- All UI state on `@MainActor`; `async/await` throughout.
- The app is thin I/O glue — every decision is delegated to BuddyKit.
- Do not run `xcodebuild` from the terminal (it invalidates TCC permissions).

## Logic delivered

- `BuddyApp` / `BuddyAppDelegate` — entry point + launch wiring.
- `CompanionController` — the `idle → listening → processing → responding` state machine that
  runs the full pipeline (record → transcribe → screenshot → chat → speak → point).
- `GlobalPushToTalkHotkeyMonitor` — listen-only `CGEvent` tap for Control+Option.
- `PushToTalkRecorder` — `AVAudioRecorder` capture to 16 kHz mono WAV.
- `ScreenCaptureService` — ScreenCaptureKit screenshots of every display + geometry, with the
  cursor's display marked "primary focus".
- `SpeechPlaybackService` — `AVAudioPlayer` MP3 playback.
- `CursorOverlayController` / `CursorOverlayView` — transparent full-screen `NSPanel` cursor + bubble.
- `MenuBarController` / `CompanionPanelView` — status item, floating panel, model picker, permission links.
- `AppConfiguration` — builds `BuddyConfiguration` from Info.plist + UserDefaults.

## Key variables

| Name | Value |
|------|-------|
| Bundle id | `com.ishaangupta.buddy` |
| Deployment target | macOS 14.2 |
| Push-to-talk chord | Control + Option |
| Proxy URL key | `BuddyProxyURL` (Info.plist / UserDefaults) |
| Model selection key | `BuddySelectedModelIdentifier` (UserDefaults) |

## Project generation

`project.yml` (XcodeGen) defines the target, Info.plist, entitlements, and the local `BuddyKit`
package dependency. `scripts/bootstrap.sh` runs `xcodegen generate`. The `.xcodeproj` is not committed.

## Commit

`Phase 3: macOS menu bar app — push-to-talk pipeline, ScreenCaptureKit, cursor overlay, XcodeGen project`
