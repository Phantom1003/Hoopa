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
    func body(content: Content) -> some View {
        if enabled { content.chip() } else { content.font(.system(size: 12, weight: .medium)).lineLimit(1) }
    }
}

/// The time chip: countdown (refreshed every second) or date.
struct DueChip: View {
    let due: Due
    var showDetail = true
    var bare = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let l = TimeFormat.label(due, now: ctx.date)
            HStack(spacing: 4) {
                Image(systemName: due.isCountdown ? "timer" : "calendar").font(.system(size: 11))
                Text(l.text).monospacedDigit()
                if showDetail, let d = l.detail {
                    if due.isCountdown {
                        // A countdown's due moment is derived: with a separator dot, in grey.
                        Text("·").foregroundStyle(Style.tertiary)
                        Text(d).monospacedDigit().foregroundStyle(Style.secondary)
                    } else {
                        // A date and its time are one thing: directly after, same colour.
                        Text(d).monospacedDigit()
                    }
                }
            }
            .lineLimit(1)
            .fixedSize()          // the time must never wrap to two lines
            .foregroundStyle(l.overdue ? Style.overdue : (l.urgent ? Style.urgent : Style.text))
            .modifier(OptionalChip(enabled: !bare))
            .layoutPriority(1)
        }
    }
}
