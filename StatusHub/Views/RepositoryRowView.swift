import SwiftUI

struct RepositoryRowView: View {
    let state: RepositoryState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Circle()
                    .fill(state.status.color)
                    .frame(width: 10, height: 10)
                Text(state.repositoryName)
                    .fontWeight(.medium)
                Spacer()
                Text(branchLabel)
                    .foregroundColor(.secondary)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(state.status.symbol + " " + state.status.label)
                    .font(.caption)
                    .foregroundColor(state.status.color)
            }
            bottomLine
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var bottomLine: some View {
        if let errorMessage = state.errorMessage {
            HStack {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundColor(.red)
                Spacer()
                webUrlLink
            }
        } else if isInProgress, let startedAt = state.startedAt {
            // Tick every 5s so the "elapsed" portion stays live.
            TimelineView(.periodic(from: .now, by: 5)) { context in
                progressLine(now: context.date, startedAt: startedAt)
            }
        } else if let updatedAt = state.updatedAt {
            HStack {
                Text(updatedAt, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                webUrlLink
            }
        } else {
            HStack {
                Spacer()
                webUrlLink
            }
        }
    }

    @ViewBuilder
    private func progressLine(now: Date, startedAt: Date) -> some View {
        let elapsed = max(0, now.timeIntervalSince(startedAt))
        HStack(spacing: 8) {
            if let baseline = state.baselineDuration, baseline > 0 {
                let ratio = min(elapsed / baseline, 1.0)
                let overrun = elapsed > baseline
                ProgressView(value: ratio)
                    .progressViewStyle(.linear)
                    .tint(overrun ? .orange : .blue)
                    .frame(maxWidth: 120)
                Text(progressLabel(elapsed: elapsed, baseline: baseline, overrun: overrun))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                Text("已运行 \(formatDuration(elapsed))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            webUrlLink
        }
    }

    private func progressLabel(elapsed: TimeInterval, baseline: TimeInterval, overrun: Bool) -> String {
        let e = formatDuration(elapsed)
        let b = formatDuration(baseline)
        if overrun {
            return "\(e)（超过历史 \(b)）"
        }
        return "\(e) / \(b)"
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        if total < 60 {
            return "\(total)s"
        }
        let m = total / 60
        let s = total % 60
        if s == 0 {
            return "\(m)m"
        }
        return "\(m)m\(s)s"
    }

    private var isInProgress: Bool {
        state.status == .running || state.status == .pending
    }

    @ViewBuilder
    private var webUrlLink: some View {
        if let webUrl = state.webUrl, let url = URL(string: webUrl) {
            Link("↗", destination: url)
                .font(.caption)
        }
    }

    private var branchLabel: String {
        if let resolved = state.resolvedBranch {
            return resolved
        }
        return state.selector.displayHint
    }
}
