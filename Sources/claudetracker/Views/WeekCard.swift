import SwiftUI

struct WeekCard: View {
    let bucket: Bucket

    var body: some View {
        SectionHeader("THIS WEEK") {
            LeadAmount(amount: bucket.cost, approximate: bucket.hasUnknownPricing)
        }
    }
}
