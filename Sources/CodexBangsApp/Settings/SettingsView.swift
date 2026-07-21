import SwiftUI

@MainActor
struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Privacy") {
                Toggle("Hide task names and locations", isOn: $model.privacyMode)
                Text("Codex-bangs reads only thread-list summary metadata; it never reads auth.json, full task prompt bodies, tool output, or diffs. A Talk to pet draft stays in memory until you explicitly open it in Codex.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Pet") {
                if model.availablePets.isEmpty {
                    Text("No valid Codex v2 pets found. The neutral fallback will be used.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Selected pet", selection: $model.selectedPetID) {
                        ForEach(model.availablePets) { pet in
                            Text(pet.manifest.displayName).tag(pet.id)
                        }
                    }
                }
            }

            Section("Codex") {
                TextField(
                    "Custom executable path (optional)",
                    text: $model.executablePath
                )
                .textFieldStyle(.roundedBorder)

                HStack {
                    Text("Status: \(model.displayStatus.label)")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Refresh") {
                        model.refresh()
                    }
                    .disabled(model.isRefreshing || model.isPreviewMode)
                }

                Text("Live Working/Waiting/Approval appears only when Codex exposes it to this monitor runtime. Recent activity is never guessed into a live state.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(16)
        .frame(width: 470, height: 360)
    }
}
