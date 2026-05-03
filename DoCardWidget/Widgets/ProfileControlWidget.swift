//
//  ProfileControlWidget.swift
//  DoCardWidget
//
//  Created by Ali Waseem on 2025-03-11.
//

import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Widget Configuration
struct ProfileControlWidget: Widget {
  let kind: String = "ProfileControlWidget"

  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: kind, intent: ProfileSelectionIntent.self, provider: ProfileControlProvider()
    ) { entry in
      ProfileWidgetEntryView(entry: entry)
        .containerBackground(for: .widget) {
          Color.black
        }
    }
    .configurationDisplayName(String(localized: "DO Profile"))
    .description(String(localized: "View and manage your selected focus profile"))
    .supportedFamilies([.systemSmall])
  }
}
