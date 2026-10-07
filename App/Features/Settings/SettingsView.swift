import SaydoCore
import SwiftData
import SwiftUI

/// 設定（実装計画 §8・§17）。
///
/// 並べるのは、追いかける時刻（朝・昼・晩）、データの書き出しと全削除、開発者向けの集計だけ。
/// `AppSettings` は `UserDefaults` の薄い包みで `@Observable` ではないので、
/// 画面は複製（`Draft`）を持ち、変わったときだけ書き戻す。朝・昼・晩の時刻が変わったら
/// 親（`onTimesChanged`）がアラームを登録し直す。
///
/// 「今日」の右上からシートで出す想定で、自分で `NavigationStack` を持つ。
@MainActor
struct SettingsView: View {

    /// 「データを全部消す」が終わったことを親へ返す。`RootView` はここでオンボーディングへ戻す
    /// （`AppSettings.reset()` で `hasCompletedOnboarding` が false に戻るため）。
    private let onDataDeleted: @MainActor () -> Void
    /// 朝・昼・晩の時刻（追う回の時刻）が変わったことを親へ返す。親はアラームを登録し直す。
    private let onTimesChanged: @MainActor () async -> Void
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

    init(
        settings: AppSettings = .shared,
        onTimesChanged: @escaping @MainActor () async -> Void = {},
        onDataDeleted: @escaping @MainActor () -> Void = {}
    ) {
        self.settings = settings
        self.onTimesChanged = onTimesChanged
        self.onDataDeleted = onDataDeleted
        _draft = State(initialValue: Draft(settings))
    }

    // MARK: - 画面の複製

    /// 画面が編集する値の束。まとめて比べられるように `Equatable` にする。
    private struct Draft: Equatable {
        var morningTime: Date
        var noonTime: Date
        var nightTime: Date

        @MainActor
        init(_ settings: AppSettings) {
            morningTime = settings.morningTime.date()
            noonTime = settings.noonTime.date()
            nightTime = settings.nightTime.date()
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
                roundTimesSection
                dataSection
                #if DEBUG
                developerSection
                #endif
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
        .onChange(of: draft) { _, new in
            guard !suppressPersist else {
                suppressPersist = false
                return
            }
            persist(new)
            scheduleReschedule()
        }
        .task { await loadStats() }
    }

    // MARK: - 追いかける時刻

    private var roundTimesSection: some View {
        Section {
            timeRow(SettingsCopy.morningTimeLabel, selection: $draft.morningTime)
            timeRow(SettingsCopy.noonTimeLabel, selection: $draft.noonTime)
            timeRow(SettingsCopy.nightTimeLabel, selection: $draft.nightTime)
        } header: {
            Text(SettingsCopy.roundTimesSection).saydoText(.sectionLabel)
        } footer: {
            Text(SettingsCopy.roundTimesFootnote).saydoText(.status)
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
                ForEach(CommitmentOutcome.allCases, id: \.self) { outcome in
                    if let count = stats.outcomeCounts[outcome], count > 0 {
                        statRow(outcome.displayName, value: SettingsCopy.count(count), detail: nil)
                    }
                }
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

    // MARK: - 保存と再登録

    private func persist(_ draft: Draft) {
        settings.morningTime = TimeOfDay(date: draft.morningTime)
        settings.noonTime = TimeOfDay(date: draft.noonTime)
        settings.nightTime = TimeOfDay(date: draft.nightTime)
    }

    /// 時刻の輪を回している間は毎目盛りで値が変わる。最後の 1 回だけ登録し直す。
    private func scheduleReschedule() {
        rescheduleTask?.cancel()
        rescheduleTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            // 朝・昼・晩の時刻は、追う回の時刻。変えたらアラームを登録し直す（実装計画 §17.9）。
            await onTimesChanged()
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
                // 旧い版が登録した保留中の通知は `NotificationScheduler` の担当（`Repository` は
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
