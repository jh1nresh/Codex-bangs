import CodexNotchPetCore
import SwiftUI

@MainActor
struct PetCreatorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var appearance = ""
    @State private var feedback: String?
    @State private var isOpeningCodex = false
    @State private var skillPresence: HatchPetSkillPresence = .missing

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Create My Pet", systemImage: "wand.and.stars")
                    .font(.title2.weight(.semibold))

                Text("Describe the character here, then review the complete $hatch-pet request in Codex before sending it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Form {
                TextField("Pet name", text: $name)
                    .textFieldStyle(.roundedBorder)

                TextField(
                    "Appearance, personality, materials, colors, and signature details",
                    text: $appearance,
                    axis: .vertical
                )
                .textFieldStyle(.roundedBorder)
                .lineLimit(4...7)
            }
            .formStyle(.grouped)

            Label(
                "The request requires the full v2 8×11 animation and direction QA before installation. Pet files stay local unless you share them.",
                systemImage: "checkmark.shield"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            skillStatus

            if let feedback {
                Text(feedback)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }

                Spacer()

                Button(continueButtonTitle) {
                    continueInCodex()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    isOpeningCodex
                        || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || appearance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
        .padding(22)
        .frame(width: 500, height: 445)
        .onAppear {
            refreshSkillPresence()
        }
    }

    @ViewBuilder
    private var skillStatus: some View {
        switch skillPresence {
        case .installed:
            Label("Your existing $hatch-pet folder will be used without changes.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .missing:
            Label("This app includes $hatch-pet. Install it locally before opening the request.", systemImage: "arrow.down.circle")
                .foregroundStyle(.secondary)
        case .blockedByExistingEntry:
            Label("The hatch-pet path already exists but is not a usable skill.", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    private var continueButtonTitle: String {
        switch skillPresence {
        case .installed:
            return "Continue in Codex"
        case .missing:
            return "Install Skill & Continue in Codex"
        case .blockedByExistingEntry:
            return "Resolve Existing Path"
        }
    }

    private var skillsRootURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("skills", isDirectory: true)
    }

    private var bundledSkillURL: URL? {
        Bundle.main.resourceURL?
            .appendingPathComponent("BundledSkills", isDirectory: true)
            .appendingPathComponent("hatch-pet", isDirectory: true)
    }

    private func refreshSkillPresence() {
        skillPresence = HatchPetSkillInstaller.presence(in: skillsRootURL)
    }

    private func continueInCodex() {
        let request: PetCreationPrompt
        do {
            request = try PetCreationPrompt(name: name, appearance: appearance)
            feedback = request.wasAppearanceTruncated
                ? "The description was shortened to fit the secure Codex handoff."
                : nil
        } catch let error as LocalizedError {
            feedback = error.errorDescription ?? "Check the pet description and try again."
            return
        } catch {
            feedback = "Check the pet description and try again."
            return
        }

        refreshSkillPresence()
        switch skillPresence {
        case .installed:
            openInCodex(request: request, installedSkillNow: false)
        case .blockedByExistingEntry:
            feedback = "Move \(HatchPetSkillInstaller.destinationURL(in: skillsRootURL).path) aside yourself, then try again. Codex-bangs will never replace it."
        case .missing:
            installSkillAndOpen(request: request)
        }
    }

    private func installSkillAndOpen(request: PetCreationPrompt) {
        guard let bundledSkillURL else {
            feedback = "This app build is missing the bundled hatch-pet skill. Download a fresh Codex-bangs release."
            return
        }

        let skillsRootURL = skillsRootURL
        isOpeningCodex = true
        feedback = "Installing $hatch-pet in your local Codex skills folder…"

        Task { @MainActor in
            do {
                _ = try await Task.detached(priority: .userInitiated) {
                    try HatchPetSkillInstaller.install(
                        bundledSkillAt: bundledSkillURL,
                        into: skillsRootURL
                    )
                }.value
                skillPresence = .installed
                openInCodex(request: request, installedSkillNow: true)
            } catch let error as LocalizedError {
                isOpeningCodex = false
                refreshSkillPresence()
                feedback = error.errorDescription ?? "Couldn't install $hatch-pet."
            } catch {
                isOpeningCodex = false
                refreshSkillPresence()
                feedback = "Couldn't install $hatch-pet. Download a fresh build or install the skill manually."
            }
        }
    }

    private func openInCodex(request: PetCreationPrompt, installedSkillNow: Bool) {
        isOpeningCodex = true
        CodexDesktopLauncher.open(prompt: request.text) { opened in
            isOpeningCodex = false
            if opened {
                dismiss()
            } else if installedSkillNow {
                feedback = "$hatch-pet was installed, but the verified Codex desktop app couldn't be opened. Open Codex and try again."
            } else {
                feedback = "Couldn't open the verified Codex desktop app."
            }
        }
    }
}
