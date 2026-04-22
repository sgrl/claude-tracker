import SwiftUI

struct TodayCard: View {
    let bucket: Bucket

    var body: some View {
        SectionHeader("TODAY") {
            LeadAmount(amount: bucket.cost, approximate: bucket.hasUnknownPricing)
        }
    }
}
