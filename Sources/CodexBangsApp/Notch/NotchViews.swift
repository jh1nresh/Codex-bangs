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
            } else if hasNotch && model.isNotchRevealed {
                CompactNotchView(
                    model: model,
                    centerGap: centerGap,
                    onExpand: onToggleExpanded
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
        .animation(reduceMotion ? nil : .snappy(duration: 0.24), value: model.isExpanded)
        .animation(reduceMotion ? nil : .snappy(duration: 0.24), value: model.isNotchRevealed)
        .onExitCommand {
            if model.isExpanded {
                onToggleExpanded()
            }
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

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("CURRENT TASK")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)

                        if model.isPreviewMode {
                            Text("PREVIEW")
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.yellow, in: Capsule())
                        }
                    }

                    Text(model.presentedTaskTitle)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .help(model.presentedTaskTitle)

                    Text(compactDetail)
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(model.petMessage == nil ? Color.secondary : Color.cyan)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))

            HStack(spacing: 8) {
                Text(model.connectionDetail)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                Button("Open details", action: onExpand)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 7)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.black.opacity(0.97))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.32), radius: 18, y: 8)
        }
        .accessibilityElement(children: .contain)
    }

    private var compactDetail: String {
        if let petMessage = model.petMessage { return petMessage }
        return model.presentedTaskLocation ?? "Click pet to wave · Double-click to play"
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
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.black.opacity(0.97))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(.white.opacity(0.10), lineWidth: 1)
                    }

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
            }
        }
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
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
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

                VStack(alignment: .leading, spacing: 4) {
                    if model.isPreviewMode {
                        Text("PREVIEW DATA")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.yellow, in: Capsule())
                            .accessibilityLabel("Preview data")
                    }

                    if let message = model.petMessage {
                        Text(message)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.cyan)
                            .transition(.opacity.combined(with: .move(edge: .leading)))
                    }

                    Text("CURRENT TASK")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)

                    Text(model.presentedTaskTitle)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
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
            .padding(10)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("TALK TO PET")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("Review before sending")
                        .font(.system(size: 9, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    TextField("What should Codex work on?", text: $model.taskDraft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...2)
                        .onChange(of: model.taskDraft) {
                            let bounded = CodexDesktopHandoff
                                .truncatingToMaximumUTF8Bytes(model.taskDraft)
                            if model.taskDraft != bounded {
                                model.taskDraft = bounded
                            }
                        }
                        .onSubmit(onOpenInCodex)

                    Button("Open in Codex", action: onOpenInCodex)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(model.taskDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let feedback = model.taskHandoffFeedback {
                    Text(feedback)
                        .font(.system(size: 9, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 6) {
                Text("USAGE")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                if model.usageRows.isEmpty {
                    Text("No usage windows available")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(model.usageRows) { row in
                                UsageRowView(row: row, isStale: model.isStale)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .frame(maxHeight: 78)
                }
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
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.black.opacity(0.96))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.35), radius: 20, y: 8)
        }
        .accessibilityElement(children: .contain)
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
                .font(.system(size: 11, weight: .semibold, design: .rounded))
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
                .font(.system(size: 11, weight: .bold, design: .rounded))
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
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
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
