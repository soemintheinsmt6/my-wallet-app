import SwiftUI
import WidgetKit

@main
struct WalletWidgetBundle: WidgetBundle {
    var body: some Widget {
        BalanceWidget()
        MonthlySpendingWidget()
        RecentRecordsWidget()
        BudgetProgressWidget()
        QuickAddWidget()
    }
}
