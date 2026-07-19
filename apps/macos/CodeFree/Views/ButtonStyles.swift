import AppKit
import SwiftUI

// MARK: - Interaction helpers

enum InteractionFeedback {
    /// Light click feedback for primary actions (send, create).
    static func click() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
    }
}

// MARK: - Quiet control (sidebar rows, icon tools)

/// Borderless control with hover fill + press dim. For labels that bring their own layout.
struct QuietButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 6
    var hoverOpacity: Double = 0.08
    var pressedOpacity: Double = 0.14

    func makeBody(configuration: Configuration) -> some View {
        QuietButtonBody(
            configuration: configuration,
            cornerRadius: cornerRadius,
            hoverOpacity: hoverOpacity,
            pressedOpacity: pressedOpacity
        )
    }
}

private struct QuietButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let cornerRadius: CGFloat
    let hoverOpacity: Double
    let pressedOpacity: Double
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(fillOpacity))
            )
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed && isEnabled ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: hovering)
            .onHover { hovering = $0 }
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var fillOpacity: Double {
        guard isEnabled else { return 0 }
        if configuration.isPressed { return pressedOpacity }
        if hovering { return hoverOpacity }
        return 0
    }
}

// MARK: - Selector chip (folder / harness menus)

/// Capsule chip with hover lift and press. Use on Menu labels and plain chip buttons.
struct ChipButtonStyle: ButtonStyle {
    var emphasized: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        ChipButtonBody(configuration: configuration, emphasized: emphasized)
    }
}

private struct ChipButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let emphasized: Bool
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .opacity(isEnabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed && isEnabled ? 0.97 : 1)
            .brightness(hovering && isEnabled && !configuration.isPressed ? 0.02 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: hovering)
            .onHover { hovering = $0 }
            .contentShape(Capsule())
    }
}

// MARK: - Send (circular primary)

struct SendButtonStyle: ButtonStyle {
    var isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        SendButtonBody(configuration: configuration, isActive: isActive)
    }
}

private struct SendButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let isActive: Bool
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .scaleEffect(scale)
            .opacity(isEnabled ? 1 : 0.55)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: hovering)
            .onHover { hovering = $0 }
            .contentShape(Circle())
    }

    private var scale: CGFloat {
        guard isEnabled else { return 1 }
        if configuration.isPressed { return 0.90 }
        if hovering && isActive { return 1.05 }
        return 1
    }
}

// MARK: - Matrix / pick-list cell

struct SelectableCellButtonStyle: ButtonStyle {
    var isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        SelectableCellBody(configuration: configuration, isSelected: isSelected)
    }
}

private struct SelectableCellBody: View {
    let configuration: ButtonStyleConfiguration
    let isSelected: Bool
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .opacity(isEnabled ? 1 : 0.35)
            .scaleEffect(configuration.isPressed && isEnabled ? 0.92 : 1)
            .brightness(hovering && isEnabled && !isSelected && !configuration.isPressed ? 0.03 : 0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: hovering)
            .animation(.easeInOut(duration: 0.15), value: isSelected)
            .onHover { hovering = $0 }
    }
}

// MARK: - Prominent recovery (restart, etc.)

struct SoftProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SoftProminentBody(configuration: configuration)
    }
}

private struct SoftProminentBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.body.weight(.semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(fillOpacity))
            )
            .foregroundStyle(Color.white.opacity(isEnabled ? 1 : 0.7))
            .scaleEffect(configuration.isPressed && isEnabled ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: hovering)
            .onHover { hovering = $0 }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var fillOpacity: Double {
        guard isEnabled else { return 0.35 }
        if configuration.isPressed { return 0.85 }
        if hovering { return 0.95 }
        return 1
    }
}
