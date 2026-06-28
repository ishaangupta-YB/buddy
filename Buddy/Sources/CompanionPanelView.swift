import SwiftUI
import AppKit
import BuddyKit

/// The dark, rounded control panel shown when the user clicks Buddy's menu bar icon.
///
/// It surfaces the live companion status, the push-to-talk instructions, a model picker
/// restricted to vision-capable Cloudflare Workers AI models, quick links to the macOS
/// permission panes Buddy needs, and a quit button.
struct CompanionPanelView: View {
    @ObservedObject var companionController: CompanionController
    let onQuitRequested: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            statusRow
            pushToTalkHint
            modelPicker
            Divider().overlay(Color.white.opacity(0.08))
            permissionButtons
            quitButton
        }
        .padding(18)
        .frame(width: 320, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.09, green: 0.09, blue: 0.11))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(Color.blue)
            Text("Buddy")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.white)
            Spacer()
            Text("Cloudflare Workers AI")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.45))
        }
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 9, height: 9)
            Text(statusText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.85))
        }
    }

    private var pushToTalkHint: some View {
        Text("Hold Control + Option, speak your question, then release. Buddy sees your screen and answers out loud.")
            .font(.system(size: 12))
            .foregroundStyle(Color.white.opacity(0.6))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var modelPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Model")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.5))
            Picker("Model", selection: $companionController.selectedChatModel) {
                ForEach(WorkersAIModelCatalog.visionCapableModels, id: \.modelIdentifier) { chatModel in
                    Text(chatModel.displayName).tag(chatModel)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    private var permissionButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Buddy needs Screen Recording, Microphone, and Accessibility access.")
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                permissionLinkButton(title: "Screen", settingsPaneURL: screenRecordingSettingsURL)
                permissionLinkButton(title: "Mic", settingsPaneURL: microphoneSettingsURL)
                permissionLinkButton(title: "Accessibility", settingsPaneURL: accessibilitySettingsURL)
            }
        }
    }

    private func permissionLinkButton(title: String, settingsPaneURL: URL?) -> some View {
        Button(action: {
            if let settingsPaneURL {
                NSWorkspace.shared.open(settingsPaneURL)
            }
        }) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.9))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .pointerStyleOnHover()
    }

    private var quitButton: some View {
        Button(action: onQuitRequested) {
            Text("Quit Buddy")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.8))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
        .pointerStyleOnHover()
    }

    private var statusText: String {
        switch companionController.voiceState {
        case .idle: return "Ready"
        case .listening: return "Listening…"
        case .processing: return "Thinking…"
        case .responding: return "Responding…"
        }
    }

    private var statusColor: Color {
        switch companionController.voiceState {
        case .idle: return Color.green
        case .listening: return Color.blue
        case .processing: return Color.orange
        case .responding: return Color.purple
        }
    }

    private var screenRecordingSettingsURL: URL? {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    private var microphoneSettingsURL: URL? {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }

    private var accessibilitySettingsURL: URL? {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }
}

private extension View {
    /// Shows the pointing-hand cursor on hover, satisfying Buddy's rule that every interactive
    /// element communicates clickability.
    func pointerStyleOnHover() -> some View {
        onHover { isHovering in
            if isHovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
