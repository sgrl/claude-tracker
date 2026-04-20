import SwiftUI
import Charts

struct WeekCard: View {
    let bucket: Bucket
    let dailyLast7: [DailyBucket]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader("THIS WEEK") {
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
            if !dailyLast7.isEmpty {
                DailyCostChart(days: dailyLast7)
                    .frame(height: 40)
                    .padding(.top, 2)
            }
        }
    }
}

private struct DailyCostChart: View {
    let days: [DailyBucket]

    private var todayKey: Date { Calendar.current.startOfDay(for: Date()) }

    var body: some View {
        Chart(days) { item in
            BarMark(
                x: .value("Day", item.day, unit: .day),
                y: .value("Cost", item.bucket.cost)
            )
            .foregroundStyle(item.day == todayKey ? Color.accentColor : Color.accentColor.opacity(0.55))
            .cornerRadius(2)
            .annotation(position: .top, alignment: .center, spacing: 1) {
                if item.bucket.cost > 0 {
                    Text(Fmt.dollars(item.bucket.cost))
                        .font(.system(size: 8).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
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
