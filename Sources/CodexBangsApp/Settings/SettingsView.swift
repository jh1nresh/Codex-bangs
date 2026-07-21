import SwiftUI

@MainActor
struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var isChoosingPet = false
    @State private var isCreatingPet = false
    @State private var isDropTarget = false

    var body: some View {
        Form {
            Section("Privacy") {
                Toggle("Hide task names and locations", isOn: $model.privacyMode)
                Text("Codex-bangs reads only thread-list summary metadata; it never reads auth.json, full task prompt bodies, tool output, or diffs. A Talk to pet draft stays in memory until you explicitly open it in Codex.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Pet") {
                Picker("Selected pet", selection: $model.selectedPetID) {
                    Label("Bloop — Built-in", systemImage: "sparkles")
                        .tag(AppModel.builtInPetID)

                    ForEach(model.availablePets) { pet in
                        Text(pet.manifest.displayName).tag(pet.id)
                    }
                }

                HStack(spacing: 8) {
                    Button("Import .codexpet…") {
                        isChoosingPet = true
                    }
                    .disabled(model.isImportingPet)

                    Button("Create My Pet…") {
                        isCreatingPet = true
                    }

                    Spacer()

                    Button {
                        model.reloadPets()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Reload installed pets")
                    .accessibilityLabel("Reload installed pets")
                    .disabled(model.isImportingPet)
                }

                Label(
                    isDropTarget
                        ? "Drop to import and select"
                        : "Drop a .codexpet package here, or double-click one in Finder.",
                    systemImage: isDropTarget ? "arrow.down.circle.fill" : "shippingbox"
                )
                .font(.caption)
                .foregroundStyle(isDropTarget ? Color.accentColor : Color.secondary)

                if let feedback = model.petImportFeedback {
                    Label(
                        feedback.message,
                        systemImage: feedback.isError
                            ? "exclamationmark.triangle.fill"
                            : "checkmark.circle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(feedback.isError ? Color.orange : Color.green)
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
        .frame(width: 500, height: 470)
        .fileImporter(
            isPresented: $isChoosingPet,
            allowedContentTypes: [.codexPetPackage],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                model.importPetPackage(at: url)
            case .failure(let error):
                model.recordPetImportPickerFailure(error)
            }
        }
        .sheet(isPresented: $isCreatingPet) {
            PetCreatorView()
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let packageURL = urls.first(where: {
                $0.pathExtension.caseInsensitiveCompare("codexpet") == .orderedSame
            }) else {
                return false
            }
            return model.importPetPackage(at: packageURL)
        } isTargeted: { targeted in
            isDropTarget = targeted
        }
    }
}
