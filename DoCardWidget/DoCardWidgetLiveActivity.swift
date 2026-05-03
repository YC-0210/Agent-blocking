import ActivityKit
import SwiftUI
import WidgetKit

struct DoCardWidgetAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    var startTime: Date
    var scheduledEndTime: Date? = nil  // nil = non-timer session (elapsed display)
    var isBreakActive: Bool = false
    var breakStartTime: Date?
    var breakEndTime: Date?
  }

  var name: String
  var message: String
}

struct DoCardWidgetLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: DoCardWidgetAttributes.self) { context in

      // MARK: Lock Screen Banner
      ZStack {
        Color.black

        HStack {
          Image("DOLogo")
            .resizable()
            .scaledToFit()
            .frame(width: 40, height: 40)

          Spacer()

          Text(
            context.state.scheduledEndTime ?? context.state.startTime,
            style: .timer
          )
          .font(.system(size: 36, weight: .thin))
          .foregroundColor(Color("AccentColor"))
          .monospacedDigit()
        }
        .padding(.horizontal, 16)
      }

    } dynamicIsland: { context in
      DynamicIsland {

        // MARK: Dynamic Island — Expanded
        DynamicIslandExpandedRegion(.center) {
          HStack(alignment: .center, spacing: 12) {
            Image("DOLogo")
              .resizable()
              .scaledToFit()
              .frame(width: 32, height: 32)

            Group {
              if let endTime = context.state.scheduledEndTime {
                Text(endTime, style: .timer)
              } else {
                Text(context.state.startTime, style: .timer)
              }
            }
            .font(.system(size: 28, weight: .thin))
            .foregroundColor(Color("AccentColor"))
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .trailing)
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 4)
        }

      } compactLeading: {

        // MARK: Dynamic Island — Compact Leading
        Image("DOLogo")
          .resizable()
          .scaledToFit()
          .frame(width: 36, height: 36)

      } compactTrailing: {

        // MARK: Dynamic Island — Compact Trailing
        Group {
          if let endTime = context.state.scheduledEndTime {
            Text(endTime, style: .timer)
          } else {
            Text(context.state.startTime, style: .timer)
          }
        }
        .font(.system(size: 14, weight: .thin))
        .foregroundColor(Color("AccentColor"))
        .monospacedDigit()
        .frame(maxWidth: .infinity, alignment: .trailing)

      } minimal: {

        // MARK: Dynamic Island — Minimal
        Image("DOLogo")
          .resizable()
          .scaledToFit()
          .frame(width: 20, height: 20)

      }
      .keylineTint(Color("AccentColor"))
    }
  }
}

extension DoCardWidgetAttributes {
  fileprivate static var preview: DoCardWidgetAttributes {
    DoCardWidgetAttributes(
      name: "Focus Session",
      message: "")
  }
}

extension DoCardWidgetAttributes.ContentState {
  // Non-timer session: elapsed 1 hour 1 minute
  fileprivate static var shortTime: DoCardWidgetAttributes.ContentState {
    DoCardWidgetAttributes.ContentState(
      startTime: Date(timeInterval: -3660, since: Date.now),
      scheduledEndTime: nil,
      isBreakActive: false,
      breakStartTime: nil,
      breakEndTime: nil
    )
  }

  // Non-timer session: elapsed 2 hours 1 minute
  fileprivate static var longTime: DoCardWidgetAttributes.ContentState {
    DoCardWidgetAttributes.ContentState(
      startTime: Date(timeInterval: -7260, since: Date.now),
      scheduledEndTime: nil,
      isBreakActive: false,
      breakStartTime: nil,
      breakEndTime: nil
    )
  }

  // Timer session: 20 minutes remaining
  fileprivate static var timerSession: DoCardWidgetAttributes.ContentState {
    DoCardWidgetAttributes.ContentState(
      startTime: Date(timeInterval: -300, since: Date.now),
      scheduledEndTime: Date(timeInterval: 1200, since: Date.now),
      isBreakActive: false,
      breakStartTime: nil,
      breakEndTime: nil
    )
  }
}

#Preview("Notification", as: .content, using: DoCardWidgetAttributes.preview) {
  DoCardWidgetLiveActivity()
} contentStates: {
  DoCardWidgetAttributes.ContentState.shortTime
  DoCardWidgetAttributes.ContentState.longTime
  DoCardWidgetAttributes.ContentState.timerSession
}
