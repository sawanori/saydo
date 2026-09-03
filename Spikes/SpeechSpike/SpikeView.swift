import SwiftUI

struct SpikeView: View {
    @State private var controller = SpikeController.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    stageSection
                    waveformSection
                    transcriptSection
                    controlSection
                    localeSection
                    notificationSection
                    formatSection
                    logSection
                }
                .padding(20)
            }
            .navigationTitle("SpeechSpike")
        }
        .onAppear { controller.onAppear() }
    }

    // MARK: 状態

    private var stageSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(controller.stage.rawValue)
                .font(.title2.bold())
            Text("マイク権限: \(controller.micPermission)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let progress = controller.downloadProgress {
                ProgressView(value: progress) {
                    Text("ja-JP モデルをダウンロード中")
                        .font(.footnote)
                }
            }
        }
    }

    // MARK: 波形と無音

    private var waveformSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("波形（RMS）と無音の進み")
            WaveformView(samples: controller.levelHistory)
                .frame(height: 72)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            ProgressView(value: controller.silenceProgress) {
                Text(String(format: "無音 %.1f 秒で停止", controller.silenceSeconds))
                    .font(.footnote)
            }
            Picker("無音停止", selection: Binding(
                get: { controller.silenceSeconds },
                set: { controller.silenceSeconds = $0 }
            )) {
                ForEach(SpikeController.silenceChoices, id: \.self) { seconds in
                    Text(String(format: "%.1f 秒", seconds)).tag(seconds)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: 文字起こし

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("文字起こし")
            Text(controller.finalText.isEmpty ? "（確定なし）" : controller.finalText)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !controller.volatileText.isEmpty {
                Text(controller.volatileText)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: 操作

    private var controlSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("操作")
            Picker("セッションのモード", selection: Binding(
                get: { controller.sessionMode },
                set: { controller.sessionMode = $0 }
            )) {
                ForEach(SpikeSessionMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 12) {
                Button("もう一度") { controller.startTurn() }
                    .buttonStyle(.borderedProminent)
                Button("いま止める") {
                    Task { await controller.finishListening() }
                }
                .buttonStyle(.bordered)
                Button("録音を再生") { controller.playRecording() }
                    .buttonStyle(.bordered)
            }
            Button("すべて停止") { controller.stopEverything() }
                .buttonStyle(.bordered)
                .tint(.red)
        }
    }

    // MARK: ロケール

    private var localeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader("SpeechTranscriber のロケール")
            LabeledContent("isAvailable", value: String(controller.localeReport.transcriberAvailable))
            LabeledContent("supportedLocales に ja", value: mark(controller.localeReport.jaSupported))
            LabeledContent("installedLocales に ja", value: mark(controller.localeReport.jaInstalled))
            LabeledContent("supportedLocale(equivalentTo:)", value: controller.localeReport.matchedLocale ?? "なし")
            LabeledContent("AssetInventory.status", value: controller.localeReport.assetStatus)
            LabeledContent("reservedLocales", value: controller.localeReport.reserved.joined(separator: ", ").ifEmpty("なし"))
            DisclosureGroup("supportedLocales 全件（\(controller.localeReport.supported.count)）") {
                Text(controller.localeReport.supported.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            DisclosureGroup("installedLocales 全件（\(controller.localeReport.installed.count)）") {
                Text(controller.localeReport.installed.joined(separator: ", ").ifEmpty("なし"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: 通知計測

    private var notificationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("通知タップ → TTS 開始（5 回）")
            HStack(spacing: 12) {
                Button("10 秒後に通知") { controller.scheduleMeasurementNotification() }
                    .buttonStyle(.borderedProminent)
                Button("記録を消す") { controller.clearSamples() }
                    .buttonStyle(.bordered)
            }
            ForEach(Array(controller.notificationSamples.enumerated()), id: \.element.id) { index, sample in
                HStack {
                    Text("\(index + 1) 回目")
                    Spacer()
                    Text(String(format: "%.3f 秒", sample.seconds))
                        .monospacedDigit()
                        .foregroundStyle(sample.seconds <= 1.5 ? .green : .red)
                }
                .font(.callout)
            }
            if controller.notificationSamples.isEmpty {
                Text("まだ計測していない")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("1.5 秒以内: \(controller.notificationSamples.count { $0.seconds <= 1.5 }) / \(controller.notificationSamples.count)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: 形式

    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader("音声形式")
            Text(controller.audioFormatNote.isEmpty ? "（未取得）" : controller.audioFormatNote)
                .font(.caption)
                .monospaced()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: ログ

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader("ログ")
            ForEach(Array(controller.log.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.caption2)
                    .monospaced()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func mark(_ value: Bool) -> String { value ? "あり" : "なし" }
}

private struct SectionHeader: View {
    private let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.headline)
    }
}

private struct WaveformView: View {
    let samples: [Float]

    var body: some View {
        GeometryReader { geometry in
            let count = max(samples.count, 1)
            let width = geometry.size.width / CGFloat(max(count, 40))
            HStack(alignment: .center, spacing: 1) {
                ForEach(Array(samples.enumerated()), id: \.offset) { _, sample in
                    let height = min(1, CGFloat(sample) * 8) * geometry.size.height
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.accentColor)
                        .frame(width: max(width - 1, 1), height: max(height, 2))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .padding(4)
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
