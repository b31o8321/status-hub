import SwiftUI
import AppKit

struct AutomationRunsView: View {
    @ObservedObject var store: CodexAutomationStore

    var body: some View {
        VStack(spacing: 0) {
            if let error = store.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                Divider()
            }

            if store.runs.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("暂无自动化运行记录")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("~/Library/Application Support/IntelliAutomation/runs")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.runs.prefix(50)) { run in
                            AutomationRunRow(run: run, store: store)
                                .padding(.horizontal, 12)
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

private struct AutomationRunRow: View {
    let run: CodexAutomationRun
    @ObservedObject var store: CodexAutomationStore
    @State private var noteDraft: String = ""
    @State private var isEditingNote = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Circle()
                    .fill(run.status.hubStatus.color)
                    .frame(width: 9, height: 9)
                Text(run.displayTitle)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Spacer()
                Text(run.status.label)
                    .font(.caption)
                    .foregroundColor(run.status.hubStatus.color)
            }

            HStack(spacing: 8) {
                Text(timeLabel)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                if let sprint = run.sprint, !sprint.isEmpty {
                    Text(sprint)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                actionButtons
            }

            if let summary = run.summary, !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            if isEditingNote {
                HStack {
                    TextField("执行备注", text: $noteDraft)
                        .textFieldStyle(.roundedBorder)
                    Button("保存") {
                        store.saveNote(noteDraft, for: run)
                        isEditingNote = false
                    }
                    .controlSize(.small)
                }
            } else if let note = run.note, !note.isEmpty {
                Text("备注：\(note)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 7)
        .onAppear { noteDraft = run.note ?? "" }
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 8) {
            if !run.artifacts.isEmpty {
                Menu {
                    ForEach(run.artifacts) { artifact in
                        if let urlString = artifact.url, let url = URL(string: urlString) {
                            Button(artifact.title) {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "link")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("产物链接")
            }

            if let logPath = run.logPath {
                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: logPath))
                } label: {
                    Image(systemName: "doc.text")
                }
                .buttonStyle(.plain)
                .help("打开日志")
            }

            Button {
                noteDraft = run.note ?? ""
                isEditingNote.toggle()
            } label: {
                Image(systemName: "note.text")
            }
            .buttonStyle(.plain)
            .help("备注")
        }
        .font(.caption)
    }

    private var timeLabel: String {
        if run.status == .running, let startedAt = run.startedAt {
            return "开始 \(relativeFormatter.localizedString(for: startedAt, relativeTo: Date()))"
        }
        if let finishedAt = run.finishedAt {
            return relativeFormatter.localizedString(for: finishedAt, relativeTo: Date())
        }
        if let startedAt = run.startedAt {
            return relativeFormatter.localizedString(for: startedAt, relativeTo: Date())
        }
        return run.trigger ?? "未知时间"
    }

    private var relativeFormatter: RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }
}
