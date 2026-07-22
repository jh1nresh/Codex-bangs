import CodexNotchPetCore
import SwiftUI

@MainActor
struct NotchRootView: View {
    @Bindable var model: AppModel
    let centerGap: CGFloat
    let hasNotch: Bool
    let onToggleExpanded: () -> Void
    let onHoverChanged: (Bool) -> Void
    let onRefresh: () -> Void
    let onOpenInCodex: () -> Void
    let onSettings: () -> Void
    let onQuit: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if model.isExpanded {
                ExpandedNotchView(
                    model: model,
                    centerGap: centerGap,
                    hasNotch: hasNotch,
                    onCollapse: onToggleExpanded,
                    onRefresh: onRefresh,
                    onOpenInCodex: onOpenInCodex,
                    onSettings: onSettings,
                    onQuit: onQuit
                )
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    )
                )
            } else if hasNotch && model.isNotchRevealed {
                CompactNotchView(
                    model: model,
                    centerGap: centerGap,
                    onExpand: onToggleExpanded
                )
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    )
                )
            } else if !hasNotch {
                NoNotchPillView(
                    model: model,
                    centerGap: centerGap,
                    onExpand: onToggleExpanded
                )
            } else {
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover(perform: onHoverChanged)
        .environment(\.colorScheme, .dark)
        .animation(
            reduceMotion ? nil : .smooth(duration: 0.38, extraBounce: 0.0),
            value: model.isExpanded
        )
        .animation(
            reduceMotion ? nil : .smooth(duration: 0.38, extraBounce: 0.0),
            value: model.isNotchRevealed
        )
        .onExitCommand {
            if model.isExpanded {
                onToggleExpanded()
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let packageURL = urls.first(where: {
                $0.pathExtension.caseInsensitiveCompare("codexpet") == .orderedSame
            }) else {
                return false
            }
            return model.importPetPackage(at: packageURL)
        }
    }
}

@MainActor
private struct CompactNotchView: View {
    @Bindable var model: AppModel
    let centerGap: CGFloat
    let onExpand: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                StatusBadge(status: model.displayStatus)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Color.clear
                    .frame(width: centerGap)
                    .allowsHitTesting(false)

                QuotaBadge(
                    remainingPercent: model.collapsedRemainingPercent,
                    isStale: model.isStale
                )
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(height: 26)

            HStack(spacing: 12) {
                PetSpriteView(
                    package: model.selectedPet,
                    animation: model.petAnimationState,
                    onSingleClick: model.waveAtUser,
                    onDoubleClick: model.playWithUser
                )
                .frame(width: 62, height: 62)
                .petHalo()

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Current task")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .tracking(0.2)

                        if model.isPreviewMode {
                            Text("Preview")
                                .font(.system(size: 8, weight: .semibold, design: .rounded))
                                .foregroundStyle(.yellow)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.yellow.opacity(0.13), in: Capsule())
                                .overlay {
                                    Capsule().stroke(.yellow.opacity(0.22), lineWidth: 0.7)
                                }
                        }
                    }

                    Text(model.presentedTaskTitle)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .lineLimit(1)
                        .help(model.presentedTaskTitle)

                    Text(compactDetail)
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(
                            model.petMessage == nil
                                ? Color.secondary
                                : Color.cyan.opacity(0.92)
                        )
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(11)
            .softMaterialCard(cornerRadius: 16, tint: .cyan)

            HStack(spacing: 8) {
                Text(model.connectionDetail)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                detailsButton
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 7)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(NotchIslandBackground(cornerRadius: 24, shadowRadius: 18))
        .accessibilityElement(children: .contain)
    }

    private var compactDetail: String {
        if let petMessage = model.petMessage { return petMessage }
        return model.presentedTaskLocation ?? "Click pet to wave · Double-click to play"
    }

    @ViewBuilder
    private var detailsButton: some View {
        if #available(macOS 26, *) {
            Button(action: onExpand) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.down")
                        .foregroundStyle(.cyan.opacity(0.90))
                    Text("Open details")
                        .foregroundStyle(.white.opacity(0.92))
                }
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassEffect(
                .regular.tint(.cyan.opacity(0.14)).interactive(),
                in: .capsule
            )
            .accessibilityLabel("Open details")
        } else {
            Button(action: onExpand) {
                Label("Open details", systemImage: "chevron.down")
            }
            .tint(.cyan.opacity(0.82))
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
        }
    }
}

@MainActor
private struct NoNotchPillView: View {
    @Bindable var model: AppModel
    let centerGap: CGFloat
    let onExpand: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let wingWidth = max(104, (proxy.size.width - centerGap - 20) / 2)

            ZStack {
                HStack(spacing: 0) {
                    Button(action: onExpand) {
                        StatusBadge(status: model.displayStatus)
                            .frame(width: wingWidth, alignment: .leading)
                    }
                    .buttonStyle(.plain)

                    Color.clear.frame(width: centerGap)

                    Button(action: onExpand) {
                        QuotaBadge(
                            remainingPercent: model.collapsedRemainingPercent,
                            isStale: model.isStale
                        )
                        .frame(width: wingWidth, alignment: .trailing)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)

                PetSpriteView(
                    package: model.selectedPet,
                    animation: model.petAnimationState,
                    onSingleClick: model.waveAtUser,
                    onDoubleClick: model.playWithUser
                )
                .frame(width: 42, height: 42)
                .petHalo()
            }
        }
        .adaptiveFloatingGlass(cornerRadius: 18)
        .accessibilityElement(children: .contain)
    }
}

@MainActor
private struct ExpandedNotchView: View {
    @Bindable var model: AppModel
    let centerGap: CGFloat
    let hasNotch: Bool
    let onCollapse: () -> Void
    let onRefresh: () -> Void
    let onOpenInCodex: () -> Void
    let onSettings: () -> Void
    let onQuit: () -> Void

    @FocusState private var isTaskFieldFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                StatusBadge(status: model.displayStatus)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if hasNotch {
                    Color.clear
                        .frame(width: centerGap)
                        .allowsHitTesting(false)
                }

                HStack(spacing: 8) {
                    QuotaBadge(
                        remainingPercent: model.collapsedRemainingPercent,
                        isStale: model.isStale
                    )

                    Button(action: onCollapse) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 16, height: 16)
                    }
                    .controlSize(.mini)
                    .adaptiveGlassButton()
                    .accessibilityLabel("Collapse into notch")
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(height: 26)

            HStack(alignment: .center, spacing: 12) {
                PetSpriteView(
                    package: model.selectedPet,
                    animation: model.petAnimationState,
                    onSingleClick: model.waveAtUser,
                    onDoubleClick: model.playWithUser
                )
                .frame(width: 68, height: 68)
                .petHalo()

                VStack(alignment: .leading, spacing: 4) {
                    if model.isPreviewMode {
                        Text("Preview")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(.yellow)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.yellow.opacity(0.13), in: Capsule())
                            .overlay {
                                Capsule().stroke(.yellow.opacity(0.22), lineWidth: 0.7)
                            }
                            .accessibilityLabel("Preview data")
                    }

                    if let message = model.petMessage {
                        Text(message)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.cyan)
                            .transition(.opacity.combined(with: .move(edge: .leading)))
                    }

                    HStack(spacing: 8) {
                        Text("Current task")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .tracking(0.2)

                        Spacer()

                        agentMenu
                    }

                    Text(model.presentedTaskTitle)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .lineLimit(2)
                        .help(model.presentedTaskTitle)

                    if let location = model.presentedTaskLocation {
                        Text(location)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .help(location)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(11)
            .softMaterialCard(cornerRadius: 16, tint: .cyan)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Talk to pet")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(
                        model.isTalkShortcutAvailable
                            ? "Read-only · ⌃⌥Space"
                            : "Read-only · shortcut unavailable"
                    )
                        .font(.system(size: 9, design: .rounded))
                        .foregroundStyle(
                            model.isTalkShortcutAvailable
                                ? Color.secondary
                                : Color.orange
                        )
                }

                TextField("Ask a question or describe a task…", text: $model.taskDraft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...2)
                    .focused($isTaskFieldFocused)
                    .disabled(model.isRunningPetTask)
                    .onChange(of: model.taskDraft) {
                        let bounded = CodexDesktopHandoff
                            .truncatingToMaximumUTF8Bytes(model.taskDraft)
                        if model.taskDraft != bounded {
                            model.taskDraft = bounded
                        }
                    }
                    .onSubmit(model.askPet)
                    .onChange(of: model.taskFocusRequest) {
                        isTaskFieldFocused = true
                    }

                HStack(spacing: 8) {
                    if model.isRunningPetTask {
                        Button("Stop", role: .cancel, action: model.cancelPetTask)
                            .controlSize(.small)
                            .adaptiveGlassButton()
                    } else {
                        Button("Ask", action: model.askPet)
                            .tint(.cyan.opacity(0.82))
                            .controlSize(.small)
                            .adaptiveGlassButton(prominent: true)
                            .disabled(
                                model.taskDraft
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                    .isEmpty
                            )

                        Button("Guide me", action: model.guideMe)
                            .controlSize(.small)
                            .adaptiveGlassButton()
                            .help("Capture this screen once and ask Codex for read-only guidance")
                    }

                    Button("Open in Codex", action: onOpenInCodex)
                        .tint(.cyan.opacity(0.82))
                        .controlSize(.small)
                        .adaptiveGlassButton()
                        .disabled(model.taskDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Spacer()

                    if !model.activeAgentSelectedSkillIDs.isEmpty {
                        Text("\(model.activeAgentSelectedSkillIDs.count) skills")
                            .font(.system(size: 9, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                Label(
                    "Guide me: one screenshot · advice only · never controls",
                    systemImage: "eye.fill"
                )
                .font(.system(size: 9, design: .rounded))
                .foregroundStyle(.secondary)
                .accessibilityLabel(
                    "Guide me captures one screenshot for advice only and never controls your computer"
                )

                if let feedback = model.taskHandoffFeedback {
                    Text(feedback)
                        .font(.system(size: 9, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .softMaterialCard(cornerRadius: 14, tint: .indigo)

            if let response = model.taskResponse {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Pet response", systemImage: "text.bubble")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)

                    ScrollView {
                        Text(response)
                            .font(.system(size: 11, design: .rounded))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollIndicators(.hidden)
                    .frame(maxHeight: 86)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .softMaterialCard(cornerRadius: 14, tint: .cyan)
            } else {
                usageSection
            }

            HStack(spacing: 8) {
                Text(model.connectionDetail)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                Button("Refresh", action: onRefresh)
                    .disabled(model.isRefreshing || model.isPreviewMode)
                    .accessibilityLabel("Refresh Codex data")
                Button("Settings", action: onSettings)
                Button("Quit", action: onQuit)
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11, weight: .medium, design: .rounded))
        }
        .padding(.horizontal, 14)
        .padding(.top, hasNotch ? 7 : 10)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            NotchIslandBackground(
                cornerRadius: 24,
                shadowRadius: 20,
                topAttached: hasNotch
            )
        )
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var agentMenu: some View {
        Menu {
            ForEach(model.agentProfiles) { profile in
                Button {
                    model.activateAgentProfile(profile.id)
                } label: {
                    Label(
                        profile.name,
                        systemImage: profile.role.systemImageName
                    )
                }
            }
        } label: {
            Label(
                model.activeAgentProfile.name,
                systemImage: model.activeAgentProfile.role.systemImageName
            )
            .font(.system(size: 9, weight: .semibold, design: .rounded))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Summon an agent and its assigned pet")
        .accessibilityLabel("Active agent: \(model.activeAgentProfile.name)")
    }

    private var usageSection: some View {
        VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("Usage")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)

                    if model.isPreviewMode {
                        Text("Demo data")
                            .font(.system(size: 8, weight: .semibold, design: .rounded))
                            .foregroundStyle(.yellow)
                    }
                }

                if model.usageRows.isEmpty {
                    Text("No usage windows available")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(
                                Array(model.usageRows.enumerated()),
                                id: \.element.id
                            ) { index, row in
                                UsageRowView(row: row, isStale: model.isStale)

                                if index < model.usageRows.count - 1 {
                                    Divider()
                                        .overlay(.white.opacity(0.065))
                                        .padding(.leading, 9)
                                }
                            }
                        }
                        .softMaterialCard(cornerRadius: 12, tint: .white)
                    }
                    .scrollIndicators(.hidden)
                    .frame(maxHeight: 78)
                }
            }
    }
}

private struct StatusBadge: View {
    let status: AppDisplayStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(status.color)
                .frame(width: 7, height: 7)
                .overlay {
                    Circle().stroke(.white.opacity(0.25), lineWidth: 0.5)
                }

            Text(status.label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Codex status: \(status.label)")
    }
}

private struct QuotaBadge: View {
    let remainingPercent: Int?
    let isStale: Bool

    var body: some View {
        HStack(spacing: 5) {
            if isStale {
                Text("stale")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.yellow)
            }

            Text(remainingPercent.map { "\($0)% left" } ?? "—")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(quotaColor)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var quotaColor: Color {
        guard let remainingPercent else { return .secondary }
        if remainingPercent < 20 { return .red }
        if remainingPercent <= 50 { return .yellow }
        return .white.opacity(0.92)
    }

    private var accessibilityLabel: String {
        guard let remainingPercent else { return "Codex usage unavailable" }
        return "Codex usage, \(remainingPercent) percent remaining\(isStale ? ", stale" : "")"
    }
}

private struct UsageRowView: View {
    let row: UsagePresentationRow
    let isStale: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(row.label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(row.remainingPercent)% left")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()

            Text(resetLabel)
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 112, alignment: .trailing)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(row.label), \(row.remainingPercent) percent remaining, \(resetLabel)\(isStale ? ", stale" : "")"
        )
    }

    private var resetLabel: String {
        guard let reset = row.resetsAt else { return "Reset —" }
        return "Reset " + reset.formatted(
            .dateTime.weekday(.abbreviated).hour().minute()
        )
    }
}

extension AppDisplayStatus {
    var label: String {
        switch self {
        case .connecting: "Connecting"
        case .offline: "Offline"
        case .stale: "Stale"
        case .liveUnavailable: "Live unavailable"
        case .idle: "Idle"
        case .working: "Working"
        case .waiting: "Waiting"
        case .approval: "Approval"
        case .failed: "Failed"
        }
    }

    var color: Color {
        switch self {
        case .connecting: .cyan
        case .offline, .liveUnavailable: .gray
        case .stale, .waiting: .yellow
        case .idle: .white.opacity(0.75)
        case .working: .mint
        case .approval: .orange
        case .failed: .red
        }
    }
}

private struct NotchIslandBackground: View {
    let cornerRadius: CGFloat
    let shadowRadius: CGFloat
    var topAttached = true

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    var body: some View {
        if topAttached {
            surface(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: cornerRadius,
                    bottomTrailingRadius: cornerRadius,
                    topTrailingRadius: 0,
                    style: .continuous
                )
            )
        } else {
            surface(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        }
    }

    private func surface<S: InsettableShape>(_ shape: S) -> some View {
        ZStack {
            if reduceTransparency {
                shape.fill(.black)
            } else {
                shape.fill(.regularMaterial)
                shape.fill(
                    LinearGradient(
                        colors: [
                            .black.opacity(0.97),
                            Color(red: 0.035, green: 0.043, blue: 0.060).opacity(0.91),
                            Color(red: 0.055, green: 0.063, blue: 0.090).opacity(0.86),
                        ],
                        startPoint: .top,
                        endPoint: .bottomTrailing
                    )
                )
                shape.fill(
                    LinearGradient(
                        colors: [
                            .clear,
                            .indigo.opacity(0.07),
                            .cyan.opacity(0.035),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
        }
        .overlay {
            shape.strokeBorder(
                LinearGradient(
                    colors: borderColors,
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1
            )
        }
        .shadow(
            color: .black.opacity(reduceTransparency ? 0.30 : 0.24),
            radius: shadowRadius,
            y: 7
        )
    }

    private var borderColors: [Color] {
        if topAttached {
            return [
                .clear,
                .white.opacity(0.050),
                .white.opacity(0.025),
            ]
        }
        return [
            .white.opacity(reduceTransparency ? 0.10 : 0.16),
            .white.opacity(0.055),
            .white.opacity(0.025),
        ]
    }
}

private struct SoftMaterialCardBackground: View {
    let cornerRadius: CGFloat
    let tint: Color

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        ZStack {
            if reduceTransparency {
                shape.fill(Color(white: 0.10))
            } else {
                shape.fill(.regularMaterial)
                shape.fill(.black.opacity(0.28))
                shape.fill(
                    LinearGradient(
                        colors: [tint.opacity(0.055), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
        }
        .overlay {
            shape.strokeBorder(.white.opacity(0.065), lineWidth: 0.8)
        }
    }
}

private struct AdaptiveGlassButtonModifier: ViewModifier {
    let prominent: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            if prominent {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        } else if prominent {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

private struct AdaptiveFloatingGlassModifier: ViewModifier {
    let cornerRadius: CGFloat

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26, *), !reduceTransparency {
            content.glassEffect(
                .regular.tint(.black.opacity(0.32)).interactive(),
                in: .rect(cornerRadius: cornerRadius)
            )
        } else {
            content.background(
                NotchIslandBackground(
                    cornerRadius: cornerRadius,
                    shadowRadius: 14,
                    topAttached: false
                )
            )
        }
    }
}

private struct PetHaloModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content.background {
            if !reduceTransparency {
                RadialGradient(
                    colors: [
                        .white.opacity(0.075),
                        .cyan.opacity(0.035),
                        .clear,
                    ],
                    center: .center,
                    startRadius: 2,
                    endRadius: 42
                )
                .blur(radius: 4)
                .allowsHitTesting(false)
            }
        }
    }
}

private extension View {
    func softMaterialCard(
        cornerRadius: CGFloat,
        tint: Color
    ) -> some View {
        background(
            SoftMaterialCardBackground(cornerRadius: cornerRadius, tint: tint)
        )
    }

    func adaptiveGlassButton(prominent: Bool = false) -> some View {
        modifier(AdaptiveGlassButtonModifier(prominent: prominent))
    }

    func adaptiveFloatingGlass(cornerRadius: CGFloat) -> some View {
        modifier(AdaptiveFloatingGlassModifier(cornerRadius: cornerRadius))
    }

    func petHalo() -> some View {
        modifier(PetHaloModifier())
    }
}
