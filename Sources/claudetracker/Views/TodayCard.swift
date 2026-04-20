import SwiftUI
import Charts

struct TodayCard: View {
    let bucket: Bucket
    let hourly: [HourlyBucket]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader("TODAY") {
                LeadAmount(amount: bucket.cost, approximate: bucket.hasUnknownPricing)
            }
            HStack(spacing: 8) {
                Text("\(Fmt.tokens(bucket.totalTokens)) tokens")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text("·").foregroundStyle(.secondary)
                Text("\(bucket.sessionIds.count) session\(bucket.sessionIds.count == 1 ? "" : "s")")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            TokenBreakdownRow(bucket: bucket)
            if !hourly.isEmpty {
                HourlyTodayChart(hours: hourly)
                    .frame(height: 36)
                    .padding(.top, 4)
            }
        }
    }
}

struct TokenBreakdownRow: View {
    let bucket: Bucket

    var body: some View {
        HStack(spacing: 12) {
            tokenCell(label: "in",      value: bucket.inputTokens)
            tokenCell(label: "out",     value: bucket.outputTokens)
            tokenCell(label: "cache-r", value: bucket.cacheReadTokens)
            tokenCell(label: "cache-w", value: bucket.cacheWriteTokens)
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func tokenCell(label: String, value: Int) -> some View {
        HStack(spacing: 3) {
            Text(label)
            Text(Fmt.tokens(value))
                .foregroundStyle(.primary.opacity(0.8))
        }
    }
}

private struct HourlyTodayChart: View {
    let hours: [HourlyBucket]

    private var currentHour: Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day, .hour], from: Date())
        return cal.date(from: comps) ?? Date()
    }

    var body: some View {
        Chart(hours) { item in
            BarMark(
                x: .value("Hour", item.hour, unit: .hour),
                y: .value("Cost", item.bucket.cost)
            )
            .foregroundStyle(item.hour == currentHour
                             ? Color.accentColor
                             : Color.accentColor.opacity(0.55))
            .cornerRadius(1.5)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 4)) { _ in
                AxisValueLabel(format: .dateTime.hour(), centered: true)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.secondary)
            }
        }
        .chartYAxis(.hidden)
        .chartPlotStyle { plot in
            plot.background(Color.clear)
        }
    }
}
