import SwiftUI

/// The SwiftUI content rendered inside the full-screen overlay panel: a glowing cursor dot
/// that flies to pointed-at elements, and a response bubble showing Buddy's spoken reply.
struct CursorOverlayView: View {
    @ObservedObject var overlayModel: CursorOverlayModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            // The overlay itself is fully transparent and click-through; only the cursor and
            // bubble are drawn.
            Color.clear

            if overlayModel.isVisible {
                cursorCompanion
                    .position(overlayModel.cursorPositionInOverlay)
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.25), value: overlayModel.isVisible)
    }

    private var cursorCompanion: some View {
        ZStack(alignment: .topLeading) {
            cursorDot

            if !overlayModel.responseText.isEmpty {
                responseBubble
                    .offset(x: 26, y: 18)
            }
        }
    }

    private var cursorDot: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [Color.blue, Color.blue.opacity(0.65)],
                    center: .center,
                    startRadius: 1,
                    endRadius: 12
                )
            )
            .frame(width: 22, height: 22)
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.9), lineWidth: 2)
            )
            .shadow(color: Color.blue.opacity(0.6), radius: overlayModel.isPointing ? 14 : 8)
            .scaleEffect(overlayModel.isPointing ? 1.15 : 1.0)
            .animation(
                .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                value: overlayModel.isPointing
            )
    }

    private var responseBubble: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let elementLabel = overlayModel.elementLabel, !elementLabel.isEmpty {
                Text(elementLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.blue)
            }
            Text(overlayModel.responseText)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 320, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.4), radius: 12, x: 0, y: 6)
    }
}
