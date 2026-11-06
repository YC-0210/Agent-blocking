//
//  DoCardApp.swift
//  DoCard
//
//  Created by Ali Waseem on 2024-10-06.
//

import SwiftData
import SwiftUI

private let container: ModelContainer = {
  #if DEBUG && targetEnvironment(simulator)
    if let fixture = MaestroFixture.makeContainerIfRequested() { return fixture }
  #endif
  let schema = Schema(versionedSchema: AppSchemaV5.self)
  let config = ModelConfiguration(schema: schema)
  do {
    return try AppModelStore.open(configuration: config)
  } catch {
    // Strategy B: back up the corrupt store and recreate a fresh one.
    // This fires only when SwiftData cannot apply the migration plan —
    // e.g. a device whose store stamp was never correctly written and
    // whose entity hash doesn’t match any declared schema version.
    let fm = FileManager.default
    let storeURL = config.url
    let backupSuffix = "bak-\(Int(Date().timeIntervalSince1970))"

    // Back up the store and its WAL sidecars using the real `.store` filenames.
    let sidecarSuffixes = ["", "-shm", "-wal"]
    for suffix in sidecarSuffixes {
      let src =
        suffix.isEmpty
        ? storeURL
        : storeURL.deletingLastPathComponent().appendingPathComponent(
          "\(storeURL.lastPathComponent)\(suffix)"
        )
      let dst = storeURL.deletingLastPathComponent().appendingPathComponent(
        "\(storeURL.lastPathComponent)-\(backupSuffix)\(suffix)"
      )
      if fm.fileExists(atPath: src.path) {
        try? fm.moveItem(at: src, to: dst)
      }
    }

    UserDefaults.standard.set(true, forKey: "didResetStoreOnMigrationFailure")

    do {
      return try AppModelStore.open(configuration: config)
    } catch {
      fatalError("Couldn’t create ModelContainer even after store reset: \(error)")
    }
  }
}()

// This branch is the standalone agent experiment. Launch directly into its setup
// or Emergency Unlock screen; legacy onboarding and StoreKit gates are not entry points.
@main
struct DoCardApp: App {
  @UIApplicationDelegateAdaptor(AgentFocusAppDelegate.self) private var agentDelegate
  @StateObject private var agentFocus = AgentFocusRuntime.shared
  @StateObject private var requestAuthorizer = RequestAuthorizer()
  @Environment(\.scenePhase) private var scenePhase
  @State private var agentSetupError = false
  #if DEBUG
    @State private var showIconProbe = ProcessInfo.processInfo.arguments.contains(
      "--selected-app-icon-probe")
  #endif

  var body: some Scene {
    WindowGroup {
      AgentFocusView(runtime: agentFocus)
        .environmentObject(requestAuthorizer)
        #if DEBUG
          .sheet(isPresented: $showIconProbe) {
            AgentSelectedAppIconProbe(runtime: agentFocus)
          }
        #endif
        .onOpenURL { url in
          if url.scheme == "docard-agent", !agentFocus.openSetup(url) { agentSetupError = true }
        }
        .alert(
          String(localized: "Agent setup unavailable", table: "AgentFocus"),
          isPresented: $agentSetupError
        ) {
          Button("OK", role: .cancel) {}
        } message: {
          Text(agentFocus.message)
        }
        .task {
          while !Task.isCancelled {
            await agentFocus.sync()
            do { try await Task.sleep(for: .seconds(10)) } catch { break }
          }
        }
        .onChange(of: scenePhase) { _, phase in
          guard phase == .active else { return }
          Task { await agentFocus.sync() }
        }
        .preferredColorScheme(.light)
    }
    .modelContainer(container)
  }
}
