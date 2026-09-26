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

/// The timing of collapse / expand.
enum Motion {
    /// The ear slides out / back (the mask's Core Animation and the arrow's fade share this duration).
    static let earDuration: TimeInterval = 0.22
    static let ear = Animation.easeOut(duration: earDuration)
    static let earBusy: TimeInterval = 0.3
    /// The arrow on the ear: fades in only once the ear is out; disappears before the ear when it folds back.
    static let chevronIn = Animation.easeOut(duration: 0.12).delay(0.1)
    static let chevronOut = Animation.easeIn(duration: 0.1)
    /// Expand: the plate grows from the collapsed slab to the whole panel, the panel content is there from the start and is uncovered by the growing glass; the slab's content fades out meanwhile.
    static let panelGrow = Animation.smooth(duration: 0.36)
    static let compactOut = Animation.easeOut(duration: 0.12)
    static let panelContentIn = Animation.easeOut(duration: 0.15)
    static let expandBusy: TimeInterval = 0.5
    /// Collapse: the plate shrinks back to the slab's rect, covering the panel content while it fades out; then the slab's content appears.
    static let panelShrink = Animation.smooth(duration: 0.32)
    static let panelContentOut = Animation.easeIn(duration: 0.28)
    static let compactIn = Animation.easeOut(duration: 0.15).delay(0.26)
    static let parkAfter: TimeInterval = 0.4      // move out of the window only after the panel content has faded and the plate has shrunk
    static let collapseBusy: TimeInterval = 0.55
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
/// A nearly invisible tint under the glass: Liquid Glass with a custom shape writes no pixels into the window at all (and does not redraw while the custom shape animates),
/// so a transparent window treats those areas as empty and lets clicks through to the window behind (standard shapes write a little, which is why it used to be fine). With the tint, wherever the glass is, clicks and drags are caught.
/// Shapes are always standard (rounded rectangle, capsule); any other outline (the ear) is cut by the window's layer mask, see FirstMouseHostingView. glassEffectUnion does not merge, do not use it.
struct GlassBackground<S: Shape>: ViewModifier {
    let shape: S
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .background(shape.fill(Color.primary.opacity(0.03)))
                .glassEffect(.regular, in: shape)
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
