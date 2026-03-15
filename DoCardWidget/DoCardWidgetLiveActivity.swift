import ActivityKit
import SwiftUI
import WidgetKit

// DO Orange accent color
private let doOrangeColor = Color(red: 1.0, green: 0.42, blue: 0.21)

struct DoCardWidgetAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    var startTime: Date
    var isBreakActive: Bool = false
    var breakStartTime: Date?
    var breakEndTime: Date?

    func getTimeIntervalSinceNow() -> Double {
      // Calculate the break duration to subtract from elapsed time
      let breakDuration = calculateBreakDuration()

      // Calculate elapsed time minus break duration
      let adjustedStartTime = startTime.addingTimeInterval(breakDuration)

      return adjustedStartTime.timeIntervalSince1970
        - Date().timeIntervalSince1970
    }

    private func calculateBreakDuration() -> TimeInterval {
      guard let breakStart = breakStartTime else {
        return 0
      }

      if let breakEnd = breakEndTime {
        // Break is complete, return the full duration
        return breakEnd.timeIntervalSince(breakStart)
      }

      // Break is not yet ended, don't count it
      return 0
    }
  }

  var name: String
  var message: String
}

struct DoCardWidgetLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: DoCardWidgetAttributes.self) { context in
      // Lock screen/banner UI goes here
      HStack(alignment: .center, spacing: 16) {
        // Left side - App info
        VStack(alignment: .leading, spacing: 8) {
          HStack(spacing: 4) {
            Text("DO")
              .font(.headline)
              .fontWeight(.bold)
              .foregroundColor(.primary)
            Image(systemName: "hourglass")
              .foregroundColor(doOrangeColor)
          }

          Text(context.attributes.name)
            .font(.subheadline)
            .foregroundColor(.primary)

          Text(context.attributes.message)
            .font(.caption)
            .foregroundColor(.secondary)
        }

        Spacer()

        // Right side - Timer or break indicator
        VStack(alignment: .trailing, spacing: 4) {
          if context.state.isBreakActive {
            HStack(spacing: 6) {
              Image(systemName: "cup.and.heat.waves.fill")
                .font(.title2)
                .foregroundColor(.orange)
              Text(String(localized: "On a Break"))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.orange)
            }
          } else {
            Text(
              Date(
                timeIntervalSinceNow: context.state
                  .getTimeIntervalSinceNow()
              ),
              style: .timer
            )
            .font(.title)
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.trailing)
          }
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)

    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.center) {
          VStack(spacing: 8) {
            HStack(spacing: 6) {
              Image(systemName: "hourglass")
                .foregroundColor(doOrangeColor)
              Text(context.attributes.name)
                .font(.headline)
                .fontWeight(.medium)
            }

            Text(context.attributes.message)
              .font(.subheadline)
              .foregroundColor(.secondary)
              .multilineTextAlignment(.center)

            if context.state.isBreakActive {
              VStack(spacing: 2) {
                Image(systemName: "cup.and.heat.waves.fill")
                  .font(.title2)
                  .foregroundColor(.orange)
                Text(String(localized: "On a Break"))
                  .font(.subheadline)
                  .fontWeight(.semibold)
                  .foregroundColor(.orange)
              }
            } else {
              Text(
                Date(
                  timeIntervalSinceNow: context.state
                    .getTimeIntervalSinceNow()
                ),
                style: .timer
              )
              .font(.title2)
              .fontWeight(.semibold)
              .multilineTextAlignment(.center)
            }
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 4)
        }
      } compactLeading: {
        // Compact leading state
        Image(systemName: "hourglass")
          .foregroundColor(doOrangeColor)
      } compactTrailing: {
        // Compact trailing state
        Text(
          context.attributes.name
        )
        .font(.caption)
        .fontWeight(.semibold)
      } minimal: {
        // Minimal state
        Image(systemName: "hourglass")
          .foregroundColor(doOrangeColor)
      }
      .keylineTint(doOrangeColor)
    }
  }
}

extension DoCardWidgetAttributes {
  fileprivate static var preview: DoCardWidgetAttributes {
    DoCardWidgetAttributes(
      name: "Focus Session",
      message: "Stay focused and avoid distractions")
  }
}

extension DoCardWidgetAttributes.ContentState {
  fileprivate static var shortTime: DoCardWidgetAttributes.ContentState {
    DoCardWidgetAttributes
      .ContentState(
        startTime: Date(timeInterval: 60, since: Date.now),
        isBreakActive: false,
        breakStartTime: nil,
        breakEndTime: nil
      )
  }

  fileprivate static var longTime: DoCardWidgetAttributes.ContentState {
    DoCardWidgetAttributes.ContentState(
      startTime: Date(timeInterval: 60, since: Date.now),
      isBreakActive: false,
      breakStartTime: nil,
      breakEndTime: nil
    )
  }

  fileprivate static var breakActive: DoCardWidgetAttributes.ContentState {
    DoCardWidgetAttributes.ContentState(
      startTime: Date(timeInterval: 60, since: Date.now),
      isBreakActive: true,
      breakStartTime: Date.now,
      breakEndTime: nil
    )
  }
}

#Preview("Notification", as: .content, using: DoCardWidgetAttributes.preview) {
  DoCardWidgetLiveActivity()
} contentStates: {
  DoCardWidgetAttributes.ContentState.shortTime
  DoCardWidgetAttributes.ContentState.longTime
  DoCardWidgetAttributes.ContentState.breakActive
}
