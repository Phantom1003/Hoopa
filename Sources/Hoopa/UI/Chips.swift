import SwiftUI
import AppKit

/// The binding chip: app icon + page name, click to jump.
struct BindingChip: View {
    let binding: ContextBinding
    var jumping = false
    var compact = false
    var showArrow = true     // no ↗ while creating, jumping is not possible yet
    var bare = false         // no capsule background of its own (when placed inside another capsule)

    private var icon: NSImage? {
        guard let p = binding.appPath else { return nil }
        return NSWorkspace.shared.icon(forFile: p)
    }

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(nsImage: icon).resizable().frame(width: 14, height: 14)
            } else {
                Image(systemName: "macwindow").font(.caption)
            }
            if !compact {
                Text(binding.summary.isEmpty ? binding.appName : binding.summary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if jumping {
                ProgressView().controlSize(.mini)
            } else if !compact && showArrow {
                Image(systemName: "arrow.up.forward").font(.system(size: 9, weight: .bold)).foregroundStyle(Style.secondary)
            }
        }
        .foregroundStyle(Style.text)
        .modifier(OptionalChip(enabled: !bare))
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

/// The time chip: countdown (refreshed every second) + absolute time, the same for timers and date-times.
struct DueChip: View {
    let due: Due
    var showDetail = true
    var bare = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let l = TimeFormat.label(due, now: ctx.date)
            let chip = HStack(spacing: 4) {
                Text(l.text).monospacedDigit()
                if showDetail {
                    // Countdown first, the absolute time after it: with a separator dot, in grey.
                    Text("·").foregroundStyle(Style.tertiary)
                    Text(l.detail).monospacedDigit().foregroundStyle(Style.secondary)
                }
            }
            .lineLimit(1)
            .fixedSize()          // the time must never wrap to two lines
            .foregroundStyle(l.overdue ? Style.overdue : (l.urgent ? Style.urgent : Style.text))
            // The capsule tint follows the warning: orange when nearly due, red once overdue.
            .modifier(OptionalChip(enabled: !bare, tint: l.overdue ? Style.overdue.opacity(0.2)
                                                    : (l.urgent ? Style.urgent.opacity(0.15) : Style.chip)))
            .layoutPriority(1)
            // When the absolute time is not shown (collapsed) hover shows it; when shown, no tooltip, so the outer button's tooltip is not covered.
            if showDetail { chip } else { chip.help(l.detail) }
        }
    }
}
