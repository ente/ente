import SwiftUI

struct VoiceInputControls: View {
    @ObservedObject var service: VoiceTranscriptionService
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var status: String {
        switch service.state {
        case .downloading(_, let queued): return queued ? "Download queued" : "Downloading"
        case .preparing: return "Preparing"
        case .transcribing: return service.isFinishingSlow ? "Still transcribing" : "Transcribing"
        case .recording: return service.snapshot?.phase == .countdown ? "Finishing" : "Listening"
        case .error(.permission): return "Microphone access"
        case .error(.noSpeech): return "No speech"
        case .error: return "Stopped"
        case .idle: return "Preparing"
        }
    }

    private var failure: VoiceInputFailure? {
        if case .error(let failure) = service.state { return failure }
        return service.notice
    }

    var body: some View {
        if service.active || service.state.isError {
            VStack(alignment: .leading, spacing: EnsuSpacing.xs) {
                HStack(spacing: 12) {
                    Text(status).font(EnsuTypography.small).foregroundStyle(EnsuColor.textMuted)
                    if service.state.isRecording {
                        waveform.frame(height: 24)
                    } else {
                        Spacer(minLength: 0)
                    }
                    if service.active, !service.state.isRecording {
                        Button("Cancel", action: service.cancel)
                            .font(EnsuTypography.small)
                            .foregroundStyle(EnsuColor.textPrimary)
                    }
                }
                if let failure {
                    Text(failure.message)
                        .font(EnsuTypography.small)
                        .foregroundStyle(EnsuColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    if failure == .permission {
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        }
                        .font(EnsuTypography.small)
                        .foregroundStyle(EnsuColor.textPrimary)
                    }
                }
            }
        }
    }

    private var waveform: some View {
        GeometryReader { geometry in
            HStack(alignment: .center, spacing: 0) {
                ForEach(service.audioLevels.indices, id: \.self) { index in
                    let level = service.audioLevels[index]
                    Capsule()
                        .fill(EnsuColor.textPrimary.opacity(0.35 + Double(level) * 0.65))
                        .frame(
                            width: min(3, geometry.size.width / 48), height: 3 + CGFloat(level) * 21
                        )
                        .frame(
                            width: geometry.size.width / CGFloat(service.audioLevels.count),
                            height: 24)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: service.audioLevels)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Microphone activity")
    }
}

struct VoiceInputButton: View {
    @ObservedObject var service: VoiceTranscriptionService
    let enabled: Bool
    let onOpen: () -> Void

    private var canPress: Bool {
        service.active ? service.state.isRecording : enabled && !service.hasActiveTasks
    }

    private var label: String {
        switch service.state {
        case .downloading(_, let queued):
            return queued ? "Voice model download queued" : "Downloading voice model"
        case .preparing: return "Preparing voice input"
        case .transcribing: return "Transcribing"
        case .recording: return "Stop dictation"
        case .idle, .error: return "Dictate"
        }
    }

    var body: some View {
        Button {
            if service.state.isRecording {
                hapticWarning()
                service.stop()
            } else {
                onOpen()
            }
        } label: {
            ZStack {
                switch service.state {
                case .downloading(let percent, let queued):
                    if let percent, !queued {
                        Circle().stroke(EnsuColor.textMuted.opacity(0.2), lineWidth: 2)
                        Circle().trim(from: 0, to: CGFloat(min(100, max(0, percent))) / 100)
                            .stroke(
                                EnsuColor.textPrimary,
                                style: StrokeStyle(lineWidth: 2, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    Image(systemName: "arrow.down").font(.system(size: 11, weight: .semibold))
                case .preparing, .transcribing:
                    ProgressView().controlSize(.small)
                case .recording:
                    Circle().fill(EnsuColor.textPrimary).frame(width: 32, height: 32)
                    RoundedRectangle(cornerRadius: 2).fill(EnsuColor.backgroundBase)
                        .frame(width: 12, height: 12)
                case .idle, .error:
                    Image("Mic02Icon").resizable().scaledToFit().frame(width: 16, height: 16)
                }
            }
            .frame(width: 28, height: 28)
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
        }
        .foregroundStyle(canPress ? EnsuColor.textPrimary : EnsuColor.textMuted)
        .disabled(!canPress)
        .accessibilityLabel(label)
    }
}
