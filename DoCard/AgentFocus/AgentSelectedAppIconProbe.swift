#if DEBUG
  import FamilyControls
  import ManagedSettings
  import SwiftUI

  /// Local diagnostic only. Never serializes tokens or sends images/identities to the relay.
  @MainActor
  struct AgentSelectedAppIconProbe: View {
    let runtime: AgentFocusRuntime
    @Environment(\.dismiss) private var dismiss
    @State private var selection = FamilyActivitySelection()
    @State private var renders: [ApplicationToken: UIImage] = [:]
    @State private var identifiers: [ApplicationToken: String] = [:]
    @State private var message = ""
    @State private var attemptedRender = false

    var body: some View {
      NavigationStack {
        List {
          Section {
            Text("Local icon experiment")
            Text(
              "Compare the native icon on the left with the rendered image on the right. A blank or generic image is a failed capture, even if an image was returned."
            )
            Text("Nothing is uploaded. This does not change your blocked apps, limits or session.")
          }
          Section("Selected apps: \(selection.applicationTokens.count)") {
            ForEach(Array(selection.applicationTokens), id: \.self) { token in
              HStack {
                Label(token).labelStyle(.iconOnly).frame(width: 48, height: 48)
                VStack(alignment: .leading) {
                  Label(token).labelStyle(.titleOnly)
                  if let identifier = identifiers[token] {
                    Text(identifier).font(.caption)
                  }
                }
                Spacer()
                if let image = renders[token] {
                  Image(uiImage: image).resizable().frame(width: 48, height: 48)
                    .border(.secondary)
                } else {
                  Text(attemptedRender ? "No image" : "Not tested").font(.caption)
                }
              }
            }
          }
          Section {
            Button("Try rendering selected icons") { render() }
              .disabled(selection.applicationTokens.isEmpty)
            Button("Check automatic identification") { Task { await identify() } }
              .disabled(selection.applicationTokens.isEmpty)
            Text(message).font(.footnote)
          }
        }
        .navigationTitle("App icon probe")
        .toolbar { Button("Done") { dismiss() } }
        .task {
          do { selection = try runtime.editableSelection().selection } catch {
            message =
              "Cannot read the saved selection. Finish app setup and end any active session first."
          }
        }
      }
    }

    private func render() {
      renders.removeAll()
      attemptedRender = true
      for token in selection.applicationTokens {
        let renderer = ImageRenderer(
          content: Label(token).labelStyle(.iconOnly).frame(width: 48, height: 48))
        renderer.scale = 3
        if let image = renderer.uiImage { renders[token] = image }
      }
      message =
        "Renderer returned \(renders.count) of \(selection.applicationTokens.count) images. Compare every result visually; this is not proof that real icon pixels were captured."
    }

    private func identify() async {
      identifiers.removeAll()
      // Enabled only after the SDK and development provisioning profile pass preflight.
      #if DO_CARD_APP_DATA_ACCESS_PROBE
        if #available(iOS 26.4, *) {
          guard AuthorizationCenter.shared.authorizationStatus == .approvedWithDataAccess else {
            message =
              "Data access has not been approved. This probe does not request or change authorization."
            return
          }
          do {
            let applications = try await FamilyActivityData.shared.installedApplications
            for application in applications {
              guard let token = application.token, selection.applicationTokens.contains(token),
                let identifier = application.bundleIdentifier
              else { continue }
              identifiers[token] = identifier
            }
            message =
              "Matched \(identifiers.count) of \(selection.applicationTokens.count) selected apps locally. Identifiers do not provide icon image bytes."
          } catch {
            message =
              "Apple denied or could not supply installed application data. No identities were uploaded."
          }
        } else {
          message = "Automatic identification requires iOS 26.4 or later."
        }
      #else
        message =
          "Automatic identification is disabled in this build. A newer SDK and an Apple development profile with Family Controls App And Website Usage are required."
      #endif
    }
  }
#endif
