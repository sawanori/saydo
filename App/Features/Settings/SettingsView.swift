import AVFoundation
import SaydoCore
import SwiftData
import SwiftUI

/// 設定（実装計画 §8、task_013 と task_019 の UI）。
///
/// `AppSettings` は `UserDefaults` の薄い包みで `@Observable` ではないので、
/// 画面は複製（`Draft`）を持ち、変わったときだけ書き戻す。通知に関わる値が変わったら
/// `NotificationScheduler.reschedule` を呼び直す。
///
/// 「今日」の右上からシートで出す想定で、自分で `NavigationStack` を持つ。
@MainActor
struct SettingsView: View {

    /// 「データを全部消す」が終わったことを親へ返す。`RootView` はここでオンボーディングへ戻す
    /// （`AppSettings.reset()` で `hasCompletedOnboarding` が false に戻るため）。
    private let onDataDeleted: @MainActor () -> Void
    private let settings: AppSettings

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var draft: Draft
    @State private var suppressPersist = false
    @State private var rescheduleTask: Task<Void, Never>?

    @State private var exportState: ExportState = .idle
    @State private var deletionState: DeletionState = .idle
    @State private var isConfirmingDeletion = false
    @State private var stats: Repository.DeveloperStats?

    init(settings: AppSettings = .shared, onDataDeleted: @escaping @MainActor () -> Void = {}) {
        self.settings = settings
        self.onDataDeleted = onDataDeleted
        _draft = State(initialValue: Draft(settings))
    }

    // MARK: - 画面の複製

    /// 画面が編集する値の束。まとめて比べられるように `Equatable` にする。
    private struct Draft: Equatable {
        var notificationMode: NotificationMode
        var morningTime: Date
        var noonTime: Date
        var nightTime: Date
        var weekendEnabled: Bool
        var isAloneTimeSet: Bool
        var aloneTime: Date
        var speechVoiceIdentifier: String?
        var silenceThresholdSeconds: Double
        var quietModeEnabled: Bool
        var quietModeStart: Date
        var quietModeEnd: Date

        @MainActor
        init(_ settings: AppSettings) {
            notificationMode = settings.notificationMode
            morningTime = settings.morningTime.date()
            noonTime = settings.noonTime.date()
            nightTime = settings.nightTime.date()
            weekendEnabled = settings.weekendNotificationsEnabled
            isAloneTimeSet = settings.aloneTime != nil
            aloneTime = settings.effectiveAloneTime.date()
            speechVoiceIdentifier = settings.speechVoiceIdentifier
            silenceThresholdSeconds = settings.silenceThresholdSeconds
            quietModeEnabled = settings.quietModeScheduleEnabled
            quietModeStart = settings.quietModeStart.date()
            quietModeEnd = settings.quietModeEnd.date()
        }

        /// 通知の再計画が要る変更か。
        func affectsNotifications(comparedTo other: Draft) -> Bool {
            notificationMode != other.notificationMode
                || morningTime != other.morningTime
                || noonTime != other.noonTime
                || nightTime != other.nightTime
                || weekendEnabled != other.weekendEnabled
        }
    }

    private enum ExportState: Equatable {
        case idle
        case running
        case ready(url: URL, audioFileCount: Int)
        case failed
    }

    private enum DeletionState: Equatable {
        case idle
        case running
        case done(Repository.DeletionSummary)
        case failed
    }

    // MARK: - 本体

    var body: some View {
        NavigationStack {
            List {
                notificationSection
                aloneTimeSection
                voiceSection
                quietModeSection
                dataSection
                developerSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .saydoGround()
            .navigationTitle(SettingsCopy.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(SettingsCopy.close) { dismiss() }
                }
            }
        }
        .tint(SaydoTheme.Palette.accent)
        .onChange(of: draft) { old, new in
            guard !suppressPersist else {
                suppressPersist = false
                return
            }
            persist(new)
            if new.affectsNotifications(comparedTo: old) {
                scheduleReschedule()
            }
        }
        .task { await loadStats() }
    }

    // MARK: - 通知

    private var notificationSection: some View {
        Section {
            Picker(SettingsCopy.modeLabel, selection: $draft.notificationMode) {
                Text(SettingsCopy.modeTwoPerDay).tag(NotificationMode.twoPerDay)
                Text(SettingsCopy.modeThreePerDay).tag(NotificationMode.threePerDay)
            }
            timeRow(SettingsCopy.morningTimeLabel, selection: $draft.morningTime)
            if draft.notificationMode == .threePerDay {
                timeRow(SettingsCopy.noonTimeLabel, selection: $draft.noonTime)
                timeRow(SettingsCopy.nightTimeLabel, selection: $draft.nightTime)
            }
            Toggle(SettingsCopy.weekendLabel, isOn: $draft.weekendEnabled)
        } header: {
            Text(SettingsCopy.notificationSection).saydoText(.sectionLabel)
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(SettingsCopy.modeFootnote)
                Text(SettingsCopy.weekendFootnote)
            }
            .saydoText(.status)
        }
        .listRowBackground(SaydoTheme.Palette.chipFill)
    }

    // MARK: - 一人で話せる時間

    private var aloneTimeSection: some View {
        Section {
            Toggle(SettingsCopy.aloneToggle, isOn: $draft.isAloneTimeSet)
            if draft.isAloneTimeSet {
                timeRow(SettingsCopy.aloneTimeLabel, selection: $draft.aloneTime)
            }
        } header: {
            Text(SettingsCopy.aloneSection).saydoText(.sectionLabel)
        } footer: {
            Text(SettingsCopy.aloneFootnote).saydoText(.status)
        }
        .listRowBackground(SaydoTheme.Palette.chipFill)
    }

    // MARK: - 声

    private var voiceSection: some View {
        Section {
            Picker(SettingsCopy.ttsVoiceLabel, selection: $draft.speechVoiceIdentifier) {
                Text(SettingsCopy.ttsVoiceSystemDefault).tag(String?.none)
                ForEach(Self.japaneseVoices, id: \.identifier) { voice in
                    Text(
                        SettingsCopy.voiceName(
                            voice.name,
                            isHighQuality: SynthesisVoiceQuality(voice.quality) >= .enhanced
                        )
                    )
                    .tag(String?.some(voice.identifier))
                }
            }
            Picker(SettingsCopy.silenceLabel, selection: $draft.silenceThresholdSeconds) {
                ForEach(AppSettings.silenceThresholdChoices, id: \.self) { seconds in
                    Text(SettingsCopy.silenceChoice(seconds)).tag(seconds)
                }
            }
        } header: {
            Text(SettingsCopy.voiceSection).saydoText(.sectionLabel)
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if !Self.hasHighQualityJapaneseVoice {
                    Text(SettingsCopy.ttsVoiceDownloadHint)
                }
                Text(SettingsCopy.silenceFootnote)
            }
            .saydoText(.status)
        }
        .listRowBackground(SaydoTheme.Palette.chipFill)
    }

    /// 端末に入っている ja-JP の読み上げ音声。高品質を先に並べる。
    private static var japaneseVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("ja") }
            .sorted {
                let left = SynthesisVoiceQuality($0.quality)
                let right = SynthesisVoiceQuality($1.quality)
                if left == right { return $0.name < $1.name }
                return right < left
            }
    }

    private static var hasHighQualityJapaneseVoice: Bool {
        japaneseVoices.contains { SynthesisVoiceQuality($0.quality) >= .enhanced }
    }

    // MARK: - 話せない時

    private var quietModeSection: some View {
        Section {
            Toggle(SettingsCopy.quietToggle, isOn: $draft.quietModeEnabled)
            if draft.quietModeEnabled {
                timeRow(SettingsCopy.quietStartLabel, selection: $draft.quietModeStart)
                timeRow(SettingsCopy.quietEndLabel, selection: $draft.quietModeEnd)
            }
        } header: {
            Text(SettingsCopy.quietSection).saydoText(.sectionLabel)
        } footer: {
            Text(SettingsCopy.quietFootnote).saydoText(.status)
        }
        .listRowBackground(SaydoTheme.Palette.chipFill)
    }

    // MARK: - データ

    private var dataSection: some View {
        Section {
            switch exportState {
            case .idle, .failed:
                Button(SettingsCopy.exportButton) { Task { await export() } }
            case .running:
                Text(SettingsCopy.exportInProgress).saydoText(.status)
            case .ready(let url, let audioFileCount):
                Text(SettingsCopy.exportReady(fileCount: audioFileCount)).saydoText(.status)
                ShareLink(item: url) { Text(SettingsCopy.exportShare) }
            }
            if exportState == .failed {
                Text(SettingsCopy.exportFailed).saydoText(.status)
            }

            switch deletionState {
            case .idle, .failed:
                Button(SettingsCopy.deleteButton) { isConfirmingDeletion = true }
            case .running:
                Text(SettingsCopy.deleteInProgress).saydoText(.status)
            case .done(let summary):
                Text(
                    SettingsCopy.deleteDone(
                        recordCount: summary.totalRecordCount,
                        audioFileCount: summary.audioFileCount
                    )
                )
                .saydoText(.status)
            }
            if deletionState == .failed {
                Text(SettingsCopy.deleteFailed).saydoText(.status)
            }
        } header: {
            Text(SettingsCopy.dataSection).saydoText(.sectionLabel)
        } footer: {
            Text(SettingsCopy.backupNotice).saydoText(.status)
        }
        .listRowBackground(SaydoTheme.Palette.chipFill)
        .confirmationDialog(
            SettingsCopy.deleteConfirmTitle,
            isPresented: $isConfirmingDeletion,
            titleVisibility: .visible
        ) {
            Button(SettingsCopy.deleteConfirmAction, role: .destructive) {
                Task { await deleteEverything() }
            }
            Button(SettingsCopy.deleteCancel, role: .cancel) {}
        } message: {
            Text(SettingsCopy.deleteConfirmMessage)
        }
    }

    // MARK: - 開発者向け

    @ViewBuilder
    private var developerSection: some View {
        Section {
            if let stats, !stats.isEmpty {
                if let rate = stats.completionRate {
                    statRow(
                        SettingsCopy.sessionCompletionLabel,
                        value: SettingsCopy.percent(rate),
                        detail: SettingsCopy.fraction(stats.completedSessionCount, of: stats.sessionCount)
                    )
                }
                ForEach(SessionType.allCases, id: \.self) { type in
                    if let median = stats.medianDurationByType[type] {
                        statRow(
                            type.displayName,
                            value: SettingsCopy.duration(seconds: median),
                            detail: SettingsCopy.sessionDurationLabel
                        )
                    }
                }
                ForEach(CommitmentOutcome.allCases, id: \.self) { outcome in
                    if let count = stats.outcomeCounts[outcome], count > 0 {
                        statRow(outcome.displayName, value: SettingsCopy.count(count), detail: nil)
                    }
                }
                statRow(
                    SettingsCopy.shrinkLabel,
                    value: SettingsCopy.average(stats.averageShrinkCount),
                    detail: nil
                )
                statRow(
                    SettingsCopy.voicelessLabel,
                    value: SettingsCopy.count(stats.voicelessCommitmentCount),
                    detail: nil
                )
                statRow(
                    SettingsCopy.noCommitmentDaysLabel,
                    value: SettingsCopy.days(stats.daysWithoutCommitment),
                    detail: SettingsCopy.developerWindow(days: stats.windowDays)
                )
            } else {
                Text(SettingsCopy.developerEmpty).saydoText(.status)
            }
        } header: {
            Text(SettingsCopy.developerSection).saydoText(.sectionLabel)
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(SettingsCopy.outcomeLabel)
                Text(SettingsCopy.developerFootnote)
            }
            .saydoText(.status)
        }
        .listRowBackground(SaydoTheme.Palette.chipFill)
    }

    private func statRow(_ label: String, value: String, detail: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).saydoText(.list)
                if let detail {
                    Text(detail).saydoText(.status)
                }
            }
            Spacer()
            Text(value).saydoText(.time)
        }
    }

    // MARK: - 部品

    private func timeRow(_ label: String, selection: Binding<Date>) -> some View {
        DatePicker(selection: selection, displayedComponents: .hourAndMinute) {
            Text(label).saydoText(.list)
        }
    }

    // MARK: - 保存と再計画

    private func persist(_ draft: Draft) {
        settings.notificationMode = draft.notificationMode
        settings.morningTime = TimeOfDay(date: draft.morningTime)
        settings.noonTime = TimeOfDay(date: draft.noonTime)
        settings.nightTime = TimeOfDay(date: draft.nightTime)
        settings.weekendNotificationsEnabled = draft.weekendEnabled
        settings.aloneTime = draft.isAloneTimeSet ? TimeOfDay(date: draft.aloneTime) : nil
        settings.speechVoiceIdentifier = draft.speechVoiceIdentifier
        settings.silenceThresholdSeconds = draft.silenceThresholdSeconds
        settings.quietModeScheduleEnabled = draft.quietModeEnabled
        settings.quietModeStart = TimeOfDay(date: draft.quietModeStart)
        settings.quietModeEnd = TimeOfDay(date: draft.quietModeEnd)
    }

    /// 時刻の輪を回している間は毎目盛りで値が変わる。最後の 1 回だけ計画し直す。
    private func scheduleReschedule() {
        rescheduleTask?.cancel()
        let notificationSettings = settings.notificationSettings
        rescheduleTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await NotificationScheduler.shared.reschedule(settings: notificationSettings)
        }
    }

    // MARK: - 書き出し

    private func export() async {
        exportState = .running
        let exporter = DataExporter(modelContainer: modelContext.container)
        do {
            let report = try await exporter.export()
            exportState = .ready(url: report.zipURL, audioFileCount: report.includedAudioPaths.count)
        } catch {
            exportState = .failed
        }
    }

    // MARK: - 全削除

    private func deleteEverything() async {
        deletionState = .running
        let repository = Repository(modelContainer: modelContext.container)
        do {
            let summary = try await repository.deleteAll {
                // 保留中の通知は `NotificationScheduler` の担当（`Repository` は
                // `UserNotifications` を持たない）。@MainActor へ渡して取り消す。
                Task { await NotificationScheduler.shared.removeAllManagedPending() }
            }
            settings.reset()
            reloadDraftAfterReset()
            deletionState = .done(summary)
            stats = nil
            onDataDeleted()
        } catch {
            deletionState = .failed
        }
    }

    /// `reset()` のあとで画面の複製を読み直す。書き戻しは起こさない（値は既定に戻ったばかり）。
    private func reloadDraftAfterReset() {
        let fresh = Draft(settings)
        guard fresh != draft else { return }
        suppressPersist = true
        draft = fresh
    }

    // MARK: - 開発者向けの集計

    private func loadStats() async {
        let repository = Repository(modelContainer: modelContext.container)
        stats = try? await repository.developerStats()
    }
}
