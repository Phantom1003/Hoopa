import SwiftUI
import AppKit

/// The bound app's icon; a window symbol when unavailable.
struct AppIcon: View {
    let binding: ContextBinding
    var size: CGFloat = 14

    var body: some View {
        if let p = binding.appPath {
            Image(nsImage: NSWorkspace.shared.icon(forFile: p)).resizable().frame(width: size, height: size)
        } else {
            Image(systemName: "macwindow").font(.system(size: size * 0.8)).frame(width: size, height: size)
        }
    }
}

extension ContextBinding {
    /// The page name shown on chips and in the collapsed list.
    var pageName: String { summary.isEmpty ? appName : summary }
}

/// The binding chip: app icon + page name. action: a click jumps (no extra ↗, the click itself is the jump); onRemove: the × on the right removes the binding.
struct BindingChip: View {
    let binding: ContextBinding
    var jumping = false
    var bare = false                    // no capsule background of its own (when placed inside another capsule)
    var action: (() -> Void)? = nil     // click: jump (not passed when the chip sits inside another button in the composer)
    var help: String? = nil
    var onRemove: (() -> Void)? = nil   // the × on the right, removes the binding
    var minName: CGFloat? = nil         // the page name's ideal width, whatever its length: the least room a ViewThatFits must find for it
    var iconOnly = false                // the app icon alone, no page name (no room for it; the tooltip has it)

    var body: some View {
        HStack(spacing: 6) {
            ChipButton(action: action, help: help) {
                HStack(spacing: 5) {
                    AppIcon(binding: binding)
                    // The important part of a page title comes first ("Title | Site"), so truncate the tail when it does not fit, never the middle (that leaves "Ad…ion").
                    if !iconOnly {
                        Text(binding.pageName)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(idealWidth: minName)
                    }
                    if jumping { ProgressView().controlSize(.mini) }
                }
            }
            if let onRemove { ChipRemoveButton(help: "Unbind", action: onRemove) }
        }
        .foregroundStyle(Style.text)
        .modifier(OptionalChip(enabled: !bare))
    }
}

/// The clickable part of the chip: wrapped in a button only with an action (the composer's chip sits inside another button and gets no extra layer).
struct ChipButton<Content: View>: View {
    let action: (() -> Void)?
    var help: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        if let action {
            Button(action: action) { content().contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .modifier(OptionalHelp(text: help))
        } else {
            content().modifier(OptionalHelp(text: help))
        }
    }
}

/// The × at the right end of the chip: removes the binding / time.
struct ChipRemoveButton: View {
    let help: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Style.secondary)
                .frame(width: 12, height: 12).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Hover tooltip only when there is text.
struct OptionalHelp: ViewModifier {
    let text: String?
    func body(content: Content) -> some View {
        if let text { content.help(text) } else { content }
    }
}

/// No capsule background in bare mode.
struct OptionalChip: ViewModifier {
    let enabled: Bool
    var tint: Color = Style.chip
    func body(content: Content) -> some View {
        if enabled { content.chip(tint) } else { content.font(.system(size: 12, weight: .medium)).lineLimit(1) }
    }
}

/// A cell as wide as the widest of its templates, whatever it shows, its content at the trailing edge: cells given the same templates line up as a column from row to row,
/// in any language, without a fixed width. The templates are laid out hidden in the same font as the content.
struct TemplateWidth<Content: View>: View {
    let templates: [String]
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack(alignment: .trailing) {
            ForEach(templates, id: \.self) { Text($0).hidden().accessibilityHidden(true) }
            content()
        }
    }
}

/// A text-only countdown (used in the collapsed list's description row): refreshes every second, orange in the last ten minutes, red in the last minute and once overdue; hover for the absolute time.
struct DueText: View {
    let due: Due

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let l = TimeFormat.label(due, now: ctx.date)
            Text(l.text).monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(l.alert ?? Style.text)
                .help(l.detail)
        }
    }
}

/// The time chip: countdown (refreshed every second) + absolute time, the same for timers and date-times. action: a click changes the time; onRemove: the × on the right removes the time.
/// columns: the card's form, the countdown and the short time (TimeFormat.short) in cells sized by TimeFormat's templates, so the chip is as wide on every card and the times
/// line up as a column; the full absolute time is in the tooltip. Without it (the time picker) the countdown is followed by the full absolute time after a dot.
/// ring: the to-do's time ring state at a moment; with it the countdown takes the ring's colour (the same band colour as on the collapsed list's ball), red once overdue.
/// Without it (a time not yet submitted in the picker) the countdown only carries the warning colours. The absolute time stays grey either way.
struct DueChip: View {
    let due: Due
    var columns = false
    var bare = false
    var ring: ((Date) -> Ladder.State?)? = nil
    var action: (() -> Void)? = nil
    var help: String? = nil
    var onRemove: (() -> Void)? = nil

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let l = TimeFormat.label(due, now: ctx.date)
            let countdown = l.overdue ? Style.overdue : (ring?(ctx.date)?.color ?? l.alert ?? Style.text)
            HStack(spacing: 6) {
                // In columns the full absolute time is not shown: hover shows it, replacing the button's own tooltip.
                ChipButton(action: action, help: columns ? l.detail : help) {
                    if columns {
                        HStack(spacing: 6) {
                            TemplateWidth(templates: TimeFormat.countdownTemplates) { Text(l.text).foregroundStyle(countdown) }
                            TemplateWidth(templates: TimeFormat.shortTemplates) { Text(l.short).foregroundStyle(Style.secondary) }
                        }
                        .monospacedDigit()
                    } else {
                        HStack(spacing: 4) {
                            // Countdown first, the absolute time after it: with a separator dot, in grey.
                            Text(l.text).monospacedDigit().foregroundStyle(countdown)
                            Text("·").foregroundStyle(Style.tertiary)
                            Text(l.detail).monospacedDigit().foregroundStyle(Style.secondary)
                        }
                    }
                }
                if let onRemove { ChipRemoveButton(help: "Remove Time", action: onRemove) }
            }
            .lineLimit(1)
            .fixedSize()          // the time must never wrap to two lines
            .foregroundStyle(Style.text)
            // The capsule tint follows the warning (matching the time ring): orange in the last ten minutes, red in the last minute and once overdue.
            .modifier(OptionalChip(enabled: !bare, tint: l.overdue || l.critical ? Style.overdue.opacity(0.2)
                                                    : (l.urgent ? Style.urgent.opacity(0.15) : Style.chip)))
            .layoutPriority(1)
        }
    }
}
