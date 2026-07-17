import WidgetKit
import SwiftUI

@main
struct LancerWidgetsBundle: WidgetBundle {
    var body: some Widget {
        // Deployment target is iOS 27.0 (see project.yml) — well above the
        // iOS 16.2 ActivityKit push-token minimum LancerLiveActivityWidget
        // requires, so no availability gate is needed here.
        LancerLiveActivityWidget()
        AgentStatusWidget()
        PendingApprovalsWidget()
    }
}
