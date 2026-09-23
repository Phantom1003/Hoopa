import SwiftUI

/// Colours follow the system appearance: Liquid Glass adapts to light / dark desktops by itself, text uses semantic colours.
enum Style {
    static let text = Color.primary
    static let secondary = Color.secondary
    static let tertiary = Color.secondary.opacity(0.6)
    static let chip = Color.primary.opacity(0.08)
    static let chipHover = Color.primary.opacity(0.14)
    static let card = Color.primary.opacity(0.05)
    static let cardHover = Color.primary.opacity(0.09)
    static let accent = Color.accentColor
    static let urgent = Color.orange
    static let overdue = Color.red
}

/// A small capsule chip.
struct ChipStyle: ViewModifier {
    var tint: Color = Style.chip
    func body(content: Content) -> some View {
        content
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(tint))
            .contentShape(Capsule())
    }
}

extension View {
    func chip(_ tint: Color = Style.chip) -> some View { modifier(ChipStyle(tint: tint)) }
}

/// Liquid Glass background (glassEffect on macOS 26+), a translucent material on older systems.
struct GlassBackground<S: Shape>: ViewModifier {
    let shape: S
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(shape.fill(.regularMaterial))
                .overlay(shape.stroke(Color.primary.opacity(0.1)))
        }
    }
}

extension View {
    func glass<S: Shape>(_ shape: S) -> some View { modifier(GlassBackground(shape: shape)) }
}

/// Drag the window by pressing on empty space (a borderless window has no title bar). macOS 15+ uses the system's WindowDragGesture.
struct WindowDraggable: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.gesture(WindowDragGesture())
        } else {
            content
        }
    }
}

extension View {
    func windowDraggable() -> some View { modifier(WindowDraggable()) }
}

/// A Liquid Glass button (.glass on macOS 26+), a system button on older systems.
/// Selected / primary buttons avoid the solid .glassProminent; the glass is tinted with the accent colour instead, keeping its translucency.
struct GlassButton: ViewModifier {
    var prominent = false
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                content.buttonStyle(.glass).tint(Style.accent).fontWeight(.semibold)
            } else {
                content.buttonStyle(.glass)
            }
        } else {
            if prominent { content.buttonStyle(.borderedProminent) } else { content.buttonStyle(.bordered) }
        }
    }
}

/// Accent-tinted glass (dial knobs, the selected state), a translucent accent colour on older systems.
struct TintedGlass<S: Shape>: ViewModifier {
    let shape: S
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular.tint(Style.accent.opacity(0.8)).interactive(), in: shape)
        } else {
            content.background(shape.fill(Style.accent.opacity(0.4)))
        }
    }
}

extension View {
    func glassButton(prominent: Bool = false) -> some View { modifier(GlassButton(prominent: prominent)) }
    func tintedGlass<S: Shape>(_ shape: S) -> some View { modifier(TintedGlass(shape: shape)) }
}
