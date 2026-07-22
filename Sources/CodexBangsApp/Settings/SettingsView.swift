import AppKit
import CodexNotchPetCore
import SwiftUI

@MainActor
struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var selectedSection: SettingsSection = .general
    @State private var isChoosingPet = false
    @State private var isCreatingPet = false
    @State private var isDropTarget = false
    @State private var pluginManagementFeedback: String?

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Divider()
                .overlay(.white.opacity(0.06))

            ScrollView {
                sectionContent
                    .padding(28)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollIndicators(.hidden)
        }
        .frame(minWidth: 760, idealWidth: 820, minHeight: 560, idealHeight: 620)
        .background {
            LinearGradient(
                colors: [
                    Color(red: 0.035, green: 0.040, blue: 0.055),
                    Color(red: 0.055, green: 0.060, blue: 0.082),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
        .environment(\.colorScheme, .dark)
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
        .onAppear {
            model.reloadCapabilities()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Codex-bangs", systemImage: "sparkles")
                    .font(.headline)
                Text("Pet control center")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)

            ForEach(SettingsSection.allCases) { section in
                Button {
                    selectedSection = section
                } label: {
                    Label(section.title, systemImage: section.systemImageName)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 9)
                        .background {
                            if selectedSection == section {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(.white.opacity(0.10))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                                            .stroke(.white.opacity(0.08), lineWidth: 0.8)
                                    }
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedSection == section ? .isSelected : [])
            }

            Spacer()

            VStack(alignment: .leading, spacing: 5) {
                Text("Talk to pet")
                    .font(.caption.weight(.semibold))
                Text(
                    model.isTalkShortcutAvailable
                        ? "⌃⌥Space"
                        : "Shortcut unavailable"
                )
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(
                    model.isTalkShortcutAvailable
                        ? Color.cyan
                        : Color.orange
                )
                Text(
                    model.isTalkShortcutAvailable
                        ? "Opens the notch and focuses the prompt."
                        : "Another app may own ⌃⌥Space. Use Talk to pet from the menu bar."
                )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .settingsCard(tint: .cyan)
        }
        .padding(16)
        .frame(width: 190)
        .background(.black.opacity(0.18))
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .general:
            generalSection
        case .skills:
            skillsSection
        case .plugins:
            pluginsSection
        case .agents:
            agentsSection
        }
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeader(
                "Home",
                subtitle: "Choose the active companion and how it can reach Codex."
            )

            settingsGroup("Active companion", systemImage: "pawprint.fill", tint: .cyan) {
                Picker("Agent", selection: Binding(
                    get: { model.selectedAgentProfileID },
                    set: { model.activateAgentProfile($0) }
                )) {
                    ForEach(model.agentProfiles) { profile in
                        Text(profile.name).tag(profile.id)
                    }
                }

                Picker("Pet", selection: $model.selectedPetID) {
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
                        : "Drop a .codexpet here, or double-click one in Finder.",
                    systemImage: isDropTarget ? "arrow.down.circle.fill" : "shippingbox"
                )
                .font(.caption)
                .foregroundStyle(isDropTarget ? Color.cyan : Color.secondary)

                if let feedback = model.petImportFeedback {
                    feedbackLabel(feedback.message, isError: feedback.isError)
                }
            }

            settingsGroup("Codex", systemImage: "terminal", tint: .indigo) {
                TextField("Custom executable path (optional)", text: $model.executablePath)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 8) {
                    TextField(
                        "Task folder (optional; private app folder by default)",
                        text: $model.taskWorkspacePath
                    )
                    .textFieldStyle(.roundedBorder)

                    Button("Choose…", action: chooseTaskWorkspace)
                    if !model.taskWorkspacePath.isEmpty {
                        Button("Reset") {
                            model.taskWorkspacePath = ""
                        }
                    }
                }

                HStack {
                    Text("Status: \(model.displayStatus.label)")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Refresh") {
                        model.refresh()
                    }
                    .disabled(model.isRefreshing || model.isPreviewMode)
                }

                Text("Ask runs as a persisted Codex task with a read-only filesystem sandbox. Open in Codex remains the path for editable work and approvals.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            settingsGroup("Privacy", systemImage: "hand.raised.fill", tint: .mint) {
                Toggle("Hide task names and locations", isOn: $model.privacyMode)

                Text("Codex-bangs reads thread-list summary metadata. Ask sends your text plus the active role and selected skill invocation through local Codex; Codex may load that skill and read files allowed by its read-only sandbox, including the chosen task folder. Guide me also sends one screenshot only after you click it, then deletes the private temporary file. It never watches continuously or controls the computer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Label(
                    "Direct Ask and Guide me ignore user configuration, so configured plugins and MCP tools are not loaded. Use Open in Codex when you intentionally need them.",
                    systemImage: "checkmark.shield"
                )
                .font(.caption)
                .foregroundStyle(.mint)
            }
        }
    }

    private var skillsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeader(
                "Add skills",
                subtitle: "Give each agent a different workflow. Selected names are added to its Codex prompt."
            )

            HStack {
                Picker("Agent", selection: Binding(
                    get: { model.selectedAgentProfileID },
                    set: { model.activateAgentProfile($0) }
                )) {
                    ForEach(model.agentProfiles) { profile in
                        Text(profile.name).tag(profile.id)
                    }
                }
                .frame(maxWidth: 280)

                Spacer()

                Button("Open Skills Folder") {
                    NSWorkspace.shared.open(CodexCapabilityDiscovery.defaultSkillsRoot)
                }
                Button {
                    model.reloadCapabilities()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(model.isRefreshingCapabilities)
                .accessibilityLabel("Reload Codex skills")
            }

            if model.availableSkills.isEmpty {
                emptyState(
                    "No personal skills found",
                    detail: "Add a valid skill folder with SKILL.md under ~/.codex/skills, then reload. Codex-bangs detects names only; it never reads skill instructions."
                )
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(model.availableSkills) { skill in
                        Toggle(isOn: skillBinding(skill.id)) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("$\(skill.name)")
                                    .font(.system(.body, design: .monospaced).weight(.medium))
                                Text("Use with \(model.activeAgentProfile.name)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .settingsCard(tint: .indigo)
                    }
                }
            }

            Text("Skills are not pets: a skill changes how an agent approaches a request; the Agents page chooses which pet represents that agent.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var pluginsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeader(
                "Plugins",
                subtitle: "Plugins add tools, apps, and skills to Codex. Codex remains the source of truth."
            )

            HStack {
                Label(
                    "\(model.configuredPlugins.count) configured",
                    systemImage: "puzzlepiece.extension"
                )
                .foregroundStyle(.secondary)

                Spacer()

                Button("Manage in Codex…", action: openPluginManagementDraft)
                Button {
                    model.reloadCapabilities()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(model.isRefreshingCapabilities)
                .accessibilityLabel("Reload configured plugins")
            }

            if let pluginManagementFeedback {
                Text(pluginManagementFeedback)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if model.configuredPlugins.isEmpty {
                emptyState(
                    "No configured plugins found",
                    detail: "Install and enable plugins in Codex, then reload this page. Codex-bangs does not edit plugin configuration."
                )
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(model.configuredPlugins) { plugin in
                        HStack(spacing: 12) {
                            Image(systemName: "puzzlepiece.extension.fill")
                                .foregroundStyle(.cyan)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(plugin.name)
                                    .font(.body.weight(.medium))
                                Text(plugin.marketplace)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(
                                plugin.cachedPackages.last.map {
                                    "Cached \($0.version)"
                                } ?? "Configured"
                            )
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .settingsCard(tint: .cyan)
                    }
                }
            }

            Label(
                "Plugins are global Codex capabilities, not per-pet toggles. Manage installation and permissions in Codex; use Skills to specialize an individual agent.",
                systemImage: "info.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var agentsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeader(
                "Agents",
                subtitle: "Assign a pet and skills to each role, then summon it from here or the notch."
            )

            LazyVStack(spacing: 14) {
                ForEach(model.agentProfiles) { profile in
                    agentCard(profile)
                }
            }
        }
    }

    private func agentCard(_ profile: AgentPetProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: profile.role.systemImageName)
                    .font(.title3)
                    .foregroundStyle(profile.id == model.selectedAgentProfileID ? .cyan : .secondary)
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.06), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(profile.name)
                            .font(.headline)
                        if profile.id == model.selectedAgentProfileID {
                            Text("Active")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.cyan)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.cyan.opacity(0.12), in: Capsule())
                        }
                    }
                    Text(profile.role.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(profile.id == model.selectedAgentProfileID ? "Summoned" : "Summon") {
                    model.activateAgentProfile(profile.id)
                }
                .disabled(profile.id == model.selectedAgentProfileID)
            }

            Divider().overlay(.white.opacity(0.06))

            HStack(spacing: 12) {
                Picker("Pet", selection: petBinding(for: profile)) {
                    Text("Bloop — Built-in").tag(AppModel.builtInPetID)
                    ForEach(model.availablePets) { pet in
                        Text(pet.manifest.displayName).tag(pet.id)
                    }
                }

                Spacer()

                Button("Choose skills") {
                    model.activateAgentProfile(profile.id)
                    selectedSection = .skills
                }

                let installed = Set(model.availableSkills.map(\.id))
                let selectedCount = profile.selectedSkillIDs.filter(installed.contains).count
                Text("\(selectedCount) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .settingsCard(tint: profile.id == model.selectedAgentProfileID ? .cyan : .indigo)
    }

    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func settingsGroup<Content: View>(
        _ title: String,
        systemImage: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content()
        }
        .padding(16)
        .settingsCard(tint: tint)
    }

    private func emptyState(_ title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "plus.circle")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .settingsCard(tint: .indigo)
    }

    private func feedbackLabel(_ message: String, isError: Bool) -> some View {
        Label(
            message,
            systemImage: isError
                ? "exclamationmark.triangle.fill"
                : "checkmark.circle.fill"
        )
        .font(.caption)
        .foregroundStyle(isError ? Color.orange : Color.green)
    }

    private func skillBinding(_ skillID: String) -> Binding<Bool> {
        Binding(
            get: {
                model.isSkillSelected(
                    skillID,
                    for: model.selectedAgentProfileID
                )
            },
            set: { enabled in
                model.setSkill(
                    skillID,
                    enabled: enabled,
                    for: model.selectedAgentProfileID
                )
            }
        )
    }

    private func petBinding(for profile: AgentPetProfile) -> Binding<String> {
        let validIDs = Set(model.availablePets.map(\.id)).union([AppModel.builtInPetID])
        return Binding(
            get: { validIDs.contains(profile.petID) ? profile.petID : AppModel.builtInPetID },
            set: { model.assignPet($0, to: profile.id) }
        )
    }

    private func chooseTaskWorkspace() {
        let panel = NSOpenPanel()
        panel.title = "Choose a folder for Codex tasks"
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            model.taskWorkspacePath = url.path
        }
    }

    private func openPluginManagementDraft() {
        let prompt = "Help me review and manage my configured Codex plugins. Do not install, remove, enable, disable, or grant access to anything until I name the exact plugin and explicitly confirm that action."
        CodexDesktopLauncher.open(prompt: prompt) { opened in
            pluginManagementFeedback = opened
                ? "A reviewable plugin-management draft is ready in Codex."
                : "Couldn't open the verified Codex desktop app."
        }
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case skills
    case plugins
    case agents

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "Home"
        case .skills: return "Skills"
        case .plugins: return "Plugins"
        case .agents: return "Agents"
        }
    }

    var systemImageName: String {
        switch self {
        case .general: return "house.fill"
        case .skills: return "wand.and.stars"
        case .plugins: return "puzzlepiece.extension"
        case .agents: return "person.2.fill"
        }
    }
}

extension AgentPetRole {
    var systemImageName: String {
        switch self {
        case .builder: return "hammer.fill"
        case .reviewer: return "checkmark.shield.fill"
        case .guide: return "location.north.fill"
        case .custom: return "sparkles"
        }
    }

    var description: String {
        switch self {
        case .builder: return "Builds concrete results and verifies the outcome."
        case .reviewer: return "Checks correctness, evidence, and risk."
        case .guide: return "Explains the next step, including one-shot screen guidance."
        case .custom: return "A custom Codex companion role."
        }
    }
}

private struct SettingsCardModifier: ViewModifier {
    let tint: Color

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(
                .regular.tint(tint.opacity(0.08)),
                in: .rect(cornerRadius: 18)
            )
        } else {
            content
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(tint.opacity(0.035))
                        .allowsHitTesting(false)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.white.opacity(0.07), lineWidth: 0.8)
                        .allowsHitTesting(false)
                }
        }
    }
}

private extension View {
    func settingsCard(tint: Color) -> some View {
        modifier(SettingsCardModifier(tint: tint))
    }
}
