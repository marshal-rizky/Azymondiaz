import SwiftUI

struct MicButton: View {
    @StateObject private var recorder = VoiceRecorder()
    let onTranscribe: (Data) -> Void

    var body: some View {
        Image(systemName: recorder.isRecording ? "waveform.circle.fill" : "mic.circle")
            .font(.title2)
            .foregroundStyle(recorder.isRecording ? .red : .accentColor)
            .scaleEffect(1 + CGFloat(recorder.level) * 0.4)
            .animation(.easeOut(duration: 0.05), value: recorder.level)
            .gesture(
                LongPressGesture(minimumDuration: 0.1)
                    .onChanged { _ in
                        if !recorder.isRecording { try? recorder.start() }
                    }
                    .onEnded { _ in
                        if let data = recorder.stop() {
                            onTranscribe(data)
                        }
                    }
            )
            .accessibilityLabel("Hold to record")
    }
}
