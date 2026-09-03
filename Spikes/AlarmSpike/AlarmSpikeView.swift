import AlarmKit
import SwiftUI

/// スパイクの 1 画面。実機で 6 項目（消音 / 連鎖 / Open / バンドル外音 / 強制終了 / 音量）を
/// 試すためのボタンと表示だけを置く。
struct AlarmSpikeView: View {
    @State private var model = AlarmSpikeModel()
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            List {
                authorizationSection
                soundSection
                chainSection
                pendingSection
                volumeSection
                logSection
            }
            .navigationTitle("AlarmSpike")
            .listStyle(.insetGrouped)
            .task {
                model.activateSessionForVolumeReading()
                // 音量の上書き挙動を実機で目視するため、表示中は 1 秒ごとに読み直す。
                while !Task.isCancelled {
                    model.refresh()
                    try? await Task.sleep(for: .seconds(1))
                }
            }
            .overlay(alignment: .bottom) {
                if let lastError = model.lastError {
                    Text(lastError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding()
                        .background(.thinMaterial, in: .rect(cornerRadius: 12))
                        .padding()
                }
            }
        }
    }

    // MARK: 権限

    private var authorizationSection: some View {
        Section("1. 権限") {
            LabeledContent("authorizationState", value: AlarmSpikeModel.describe(model.authorizationState))
            Button("AlarmKit の権限を要求") {
                run { await model.requestAuthorization() }
            }
            .disabled(isWorking)
        }
    }

    // MARK: サウンド

    private var soundSection: some View {
        Section("2. サウンド（3 パターン）") {
            Picker("鳴らす音", selection: $model.soundMode) {
                ForEach(SpikeSoundMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()

            Toggle("ファイル名に .caf を含める", isOn: $model.includeExtension)

            LabeledContent("(b) バンドル", value: model.bundledChimeDescription)
            LabeledContent("(c) 録音", value: model.recordingState)

            Button(model.isRecording ? "録音中…" : "宣言を 10 秒録音して Library/Sounds に書く") {
                run { await model.recordDeclaration() }
            }
            .disabled(isWorking || model.isRecording)

            Text(model.declarationFileDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: 連鎖アラーム

    private var chainSection: some View {
        Section("3. 連鎖アラーム") {
            Text("2 分後から 1 分間隔で \(AlarmSpikeModel.chainCount) 件。各アラートは「開く」ボタン（secondaryButtonBehavior = .custom）付き。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("2 分後に連鎖アラーム \(AlarmSpikeModel.chainCount) 件を登録") {
                run { await model.scheduleChain() }
            }
            .disabled(isWorking)

            Button("全てのアラームを取り消す", role: .destructive) {
                model.cancelAll()
            }
            .disabled(isWorking)
        }
    }

    // MARK: pending 一覧

    private var pendingSection: some View {
        Section("4. pending（AlarmManager.shared.alarms）") {
            if model.pendingAlarms.isEmpty {
                Text("なし").foregroundStyle(.secondary)
            } else {
                ForEach(model.pendingAlarms, id: \.id) { alarm in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.describe(alarm.schedule))
                            .font(.body.monospacedDigit())
                        Text("\(alarm.id.uuidString.prefix(8))・state=\(Self.describe(alarm.state))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: 音量

    private var volumeSection: some View {
        Section("5. 出力音量（読むだけ・MPVolumeView は使わない）") {
            LabeledContent("outputVolume", value: String(format: "%.3f", model.outputVolume))
            ProgressView(value: Double(model.outputVolume))
            Text("アラーム中に音量ボタンを下げ、この値が戻るかどうかを見る。アプリから音量を変える API は使っていない。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: ログ

    private var logSection: some View {
        Section("6. ログ") {
            if model.log.isEmpty {
                Text("なし").foregroundStyle(.secondary)
            } else {
                ForEach(Array(model.log.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.caption.monospaced())
                }
            }
            Button("ログを消す") { model.clearLog() }
        }
    }

    // MARK: 補助

    private func run(_ work: @escaping @MainActor () async -> Void) {
        isWorking = true
        Task { @MainActor in
            await work()
            isWorking = false
        }
    }

    private static func describe(_ schedule: Alarm.Schedule?) -> String {
        guard let schedule else { return "スケジュール無し" }
        switch schedule {
        case .fixed(let date):
            return Self.timeFormatter.string(from: date)
        case .relative(let relative):
            return String(format: "%02d:%02d（relative）", relative.time.hour, relative.time.minute)
        @unknown default:
            return "不明なスケジュール"
        }
    }

    private static func describe(_ state: Alarm.State) -> String {
        switch state {
        case .scheduled: "scheduled"
        case .countdown: "countdown"
        case .paused: "paused"
        case .alerting: "alerting"
        @unknown default: "unknown"
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm:ss"
        return formatter
    }()
}

#Preview {
    AlarmSpikeView()
}
