import AppKit

/// Detects the system-wide push-to-talk shortcut (hold Control + Option) even while Buddy is
/// in the background.
///
/// A listen-only `CGEvent` tap on `.flagsChanged` is used rather than an AppKit global monitor
/// because modifier-only chords like Control+Option are reported far more reliably through the
/// event tap. The tap never consumes events, so it does not interfere with other apps.
@MainActor
final class GlobalPushToTalkHotkeyMonitor {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isShortcutCurrentlyHeld = false

    func startMonitoring() {
        guard eventTap == nil else { return }

        let eventMask = (1 << CGEventType.flagsChanged.rawValue)

        // `userInfo` carries an unretained pointer back to self so the C callback can reach us.
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { _, _, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<GlobalPushToTalkHotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                let modifierFlags = event.flags
                Task { @MainActor in
                    monitor.handleModifierFlagsChanged(modifierFlags)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: selfPointer
        ) else {
            // Tap creation fails when Accessibility permission has not been granted yet. The
            // panel surfaces a prompt for that; monitoring starts working once it is granted.
            return
        }

        self.eventTap = eventTap
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        self.runLoopSource = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    func stopMonitoring() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isShortcutCurrentlyHeld = false
    }

    private func handleModifierFlagsChanged(_ modifierFlags: CGEventFlags) {
        let isControlHeld = modifierFlags.contains(.maskControl)
        let isOptionHeld = modifierFlags.contains(.maskAlternate)
        let isShortcutHeldNow = isControlHeld && isOptionHeld

        if isShortcutHeldNow && !isShortcutCurrentlyHeld {
            isShortcutCurrentlyHeld = true
            onPress?()
        } else if !isShortcutHeldNow && isShortcutCurrentlyHeld {
            isShortcutCurrentlyHeld = false
            onRelease?()
        }
    }
}
