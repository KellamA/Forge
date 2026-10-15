import SwiftUI
import WidgetKit

@main
struct ForgeWidgetsBundle: WidgetBundle {
    var body: some Widget {
        UpNextWidget()
        ThisWeekWidget()
        WorkoutLiveActivity()
    }
}
