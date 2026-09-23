import SwiftUI
import AppKit

/// The binding chip: app icon + page name, click to jump.
struct BindingChip: View {
    let binding: ContextBinding
    var jumping = false
    var compact = false

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
            } else if !compact {
                Image(systemName: "arrow.up.forward").font(.system(size: 9, weight: .bold)).foregroundStyle(Style.secondary)
            }
        }
        .foregroundStyle(Style.text)
        .chip()
    }
}

/// The time chip: countdown (refreshed every second) or date.
struct DueChip: View {
    let due: Due
    var showDetail = true

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let l = TimeFormat.label(due, now: ctx.date)
            HStack(spacing: 4) {
                Image(systemName: due.isCountdown ? "timer" : "calendar").font(.system(size: 11))
                Text(l.text).monospacedDigit()
                if showDetail, let d = l.detail {
                    Text("·").foregroundStyle(Style.tertiary)
                    Text(d).monospacedDigit().foregroundStyle(Style.secondary)
                }
            }
            .lineLimit(1)
            .fixedSize()          // the time must never wrap to two lines
            .foregroundStyle(l.overdue ? Style.overdue : (l.urgent ? Style.urgent : Style.text))
            .chip(l.overdue ? Style.overdue.opacity(0.18) : Style.chip)
            .layoutPriority(1)
        }
    }
}
