import ActivityKit
import SwiftUI
import WidgetKit

@main
struct VigorWidgetsBundle: WidgetBundle {
    var body: some Widget {
        RestTimerLiveActivity()
    }
}

private let restOrange = Color(red: 1.00, green: 0.52, blue: 0.22)

/// Minuteur de repos en Live Activity : Dynamic Island + écran verrouillé.
struct RestTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestTimerAttributes.self) { context in
            RestLockScreenView(context: context)
                .activityBackgroundTint(Color(white: 0.08))
                .activitySystemActionForegroundColor(restOrange)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Repos", systemImage: "timer")
                        .font(.headline)
                        .foregroundStyle(restOrange)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RestCountdown(state: context.state, stale: context.isStale)
                        .font(.system(.title2, design: .rounded).weight(.heavy))
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(timerInterval: context.state.start...context.state.end, countsDown: true) {
                            EmptyView()
                        } currentValueLabel: {
                            EmptyView()
                        }
                        .tint(restOrange)
                        HStack {
                            Text(context.state.exercise).font(.caption.weight(.semibold)).lineLimit(1)
                            Spacer()
                            Text(context.state.next).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: "timer").foregroundStyle(restOrange)
            } compactTrailing: {
                RestCountdown(state: context.state, stale: context.isStale)
                    .font(.caption.weight(.bold))
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "timer").foregroundStyle(restOrange)
            }
            .keylineTint(restOrange)
        }
    }
}

/// Compte à rebours ; « Go » une fois le repos terminé.
struct RestCountdown: View {
    let state: RestTimerAttributes.ContentState
    let stale: Bool

    var body: some View {
        if stale || state.end <= .now {
            Text("Go").foregroundStyle(restOrange)
        } else {
            Text(timerInterval: state.start...state.end, countsDown: true)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .foregroundStyle(restOrange)
        }
    }
}

struct RestLockScreenView: View {
    let context: ActivityViewContext<RestTimerAttributes>

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "timer")
                .font(.title2.weight(.semibold))
                .foregroundStyle(restOrange)
                .frame(width: 44, height: 44)
                .background(restOrange.opacity(0.18), in: .circle)
            VStack(alignment: .leading, spacing: 4) {
                Text(context.isStale ? "Repos terminé" : "Repos · \(context.attributes.workoutTitle)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(context.state.next).font(.caption).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                ProgressView(timerInterval: context.state.start...context.state.end, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .tint(restOrange)
            }
            Spacer(minLength: 0)
            RestCountdown(state: context.state, stale: context.isStale)
                .font(.system(.title, design: .rounded).weight(.heavy))
        }
        .padding(16)
    }
}
