import SwiftUI
import Charts
import AppKit

struct SessionDetailView: View {
    let target: SessionDetailTarget
    @State private var transcript: SessionTranscript?
    @State private var isLoading: Bool = true
    @State private var loadError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let err = loadError {
                    Text(err).foregroundStyle(.red).font(.callout)
                }
                if isLoading {
                    ProgressView("Parsing transcript…")
                        .padding(.top, 32)
                } else if let t = transcript {
                    TimelineSection(hourly: t.hourly)
                    if t.modelBuckets.count > 1 {
                        ModelMixSection(models: t.modelBuckets)
                    }
                    ActivitySection(transcript: t)
                    if !t.filesTouched.isEmpty {
                        FilesTouchedSection(files: t.filesTouched)
                    }
                    actions
                }
            }
            .padding(20)
        }
        .navigationTitle(target.projectName)
        .task(id: target.sessionId) {
            await load()
        }
    }

    private func load() async {
        isLoading = true
        loadError = nil
        let url = URL(fileURLWithPath: target.transcriptPath)
        let parsed = await Task.detached(priority: .userInitiated) {
            SessionTranscriptParser.parse(jsonlURL: url)
        }.value
        self.transcript = parsed
        self.isLoading = false
        if parsed == nil {
            self.loadError = "Couldn't parse \(target.transcriptPath)"
        }
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(target.projectName)
                    .font(.title2.weight(.semibold))
                Spacer()
                if let t = transcript {
                    LeadAmount(amount: t.totalBucket.cost, approximate: t.totalBucket.hasUnknownPricing)
                        .font(.title3)
                }
            }
            HStack(spacing: 10) {
                if let cwd = target.cwd {
                    Text(cwd)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .truncationMode(.middle)
                        .lineLimit(1)
                }
            }
            if let t = transcript {
                HStack(spacing: 12) {
                    if let d = t.duration {
                        Label(Fmt.durationLong(d), systemImage: "clock")
                    }
                    if let first = t.firstTimestamp {
                        Label("Started \(Fmt.dayTime(first))", systemImage: "calendar")
                    }
                    Label("\(Fmt.tokens(t.totalBucket.totalTokens)) tokens", systemImage: "number")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 12) {
            if let cwd = target.cwd {
                Button {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: cwd)
                } label: { Label("Reveal cwd in Finder", systemImage: "folder") }
            }
            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: target.transcriptPath))
            } label: { Label("Open transcript", systemImage: "doc.text") }
            Button {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(target.sessionId, forType: .string)
            } label: { Label("Copy session ID", systemImage: "number.circle") }
            Spacer()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.top, 4)
    }
}

// MARK: - Sections

private struct TimelineSection: View {
    let hourly: [HourlyBucket]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader("HOURLY COST")
            if hourly.isEmpty {
                Text("No activity recorded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Chart(hourly) { item in
                    BarMark(
                        x: .value("Hour", item.hour, unit: .hour),
                        y: .value("Cost", item.bucket.cost)
                    )
                    .foregroundStyle(Color.accentColor.opacity(0.85))
                    .cornerRadius(2)
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { v in
                        AxisValueLabel {
                            if let d = v.as(Double.self) {
                                Text(Fmt.dollars(d))
                                    .font(.caption2.monospacedDigit())
                            }
                        }
                        AxisGridLine()
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                        AxisValueLabel(format: .dateTime.hour(), centered: true)
                            .font(.caption2)
                    }
                }
                .frame(height: 140)
            }
        }
    }
}

private struct ModelMixSection: View {
    let models: [String: Bucket]

    private var rows: [(key: String, bucket: Bucket)] {
        models.map { ($0.key, $0.value) }
            .sorted { $0.1.cost > $1.1.cost }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader("MODEL MIX")
            ForEach(rows, id: \.key) { row in
                HStack {
                    Text(displayKey(row.key))
                        .font(.body.monospacedDigit())
                    Spacer()
                    Text(Fmt.dollars(row.bucket.cost))
                        .font(.body.monospacedDigit())
                        .frame(minWidth: 64, alignment: .trailing)
                    Text(Fmt.tokens(row.bucket.totalTokens))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 64, alignment: .trailing)
                }
            }
        }
    }

    private func displayKey(_ k: String) -> String {
        k.hasPrefix("claude-") ? String(k.dropFirst("claude-".count)) : k
    }
}

private struct ActivitySection: View {
    let transcript: SessionTranscript

    private let columns: [GridItem] = [
        GridItem(.flexible()), GridItem(.flexible()),
        GridItem(.flexible()), GridItem(.flexible()),
    ]

    private var toolRows: [(name: String, count: Int)] {
        transcript.toolCounts.map { (name: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader("ACTIVITY")
            HStack(spacing: 16) {
                stat(label: "user msgs",      value: "\(transcript.userMessageCount)")
                stat(label: "assistant msgs", value: "\(transcript.assistantMessageCount)")
                stat(label: "tool calls",     value: "\(transcript.toolCounts.values.reduce(0, +))")
                stat(label: "files touched",  value: "\(transcript.filesTouched.count)")
            }
            if !toolRows.isEmpty {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                    ForEach(toolRows, id: \.name) { row in
                        HStack(spacing: 4) {
                            Text(row.name).font(.caption.monospacedDigit())
                            Text("\(row.count)")
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func stat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.monospacedDigit().weight(.semibold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct FilesTouchedSection: View {
    let files: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader("FILES TOUCHED") {
                Text("\(files.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 1) {
                ForEach(files.prefix(60), id: \.self) { path in
                    Button {
                        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                    } label: {
                        HStack {
                            Image(systemName: "doc")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(path)
                                .font(.caption.monospacedDigit())
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if files.count > 60 {
                    Text("+ \(files.count - 60) more")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }
        }
    }
}
