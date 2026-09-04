import Foundation
import SaydoCore
import SwiftData

// MARK: - 値として渡すスナップショット

/// `@Model` のクラスは Sendable ではないので、アクターの外へは値型にして返す。
/// これが Swift 6 の並行性を、検査を外す属性を使わずに満たすための土台になる。
struct CommitmentSnapshot: Sendable, Identifiable, Hashable {
    var id: UUID
    var dayKey: String
    var microAction: MicroAction
    var plannedAt: Date?
    /// 行動する場所（本人の言葉のまま。retention R11 / 統合判断 D1）。
    var plannedPlace: String?
    /// 宣言音声の相対パス。宣言の `VoiceEntry.audioPath` と同一ファイル。
    var declarationAudioPath: String?
    var declarationTranscript: String
    /// 声なしで宣言したか（fix-decisions P2.3）。
    var isVoiceless: Bool
    var outcome: CommitmentOutcome
    var reason: ReasonCategory?
    var progressNote: String?
    var createdAt: Date
    var avoidanceID: UUID?
    var avoidanceTitle: String
    var domain: TaskDomain
}

struct VoiceEntrySnapshot: Sendable, Identifiable, Hashable {
    var id: UUID
    var recordedAt: Date
    var sessionType: SessionType
    var kind: VoiceEntryKind
    var audioPath: String?
    var transcript: String
    var durationSec: Double
    var commitmentID: UUID?
}

struct CarryoverSnapshot: Sendable, Identifiable, Hashable {
    var id: UUID
    var forDayKey: String
    var text: String
    var sourceEntryID: UUID?
    var createdAt: Date
}

// MARK: - 書き込みの下書き

struct CommitmentDraft: Sendable {
    var id: UUID = UUID()
    /// 逃げたいこと（本人の言葉）。
    var avoidanceTitle: String
    var domain: TaskDomain = .other
    var reason: ReasonCategory?
    var microAction: MicroAction
    var plannedAt: Date?
    /// 行動する場所（本人の言葉のまま）。聞けなかった日は nil（統合判断 D1）。
    var plannedPlace: String?
    /// 宣言音声の相対パス。声で宣言していなければ nil。
    var declarationAudioPath: String?
    var declarationTranscript: String = ""
    var declarationDurationSec: Double = 0
    /// マイク拒否・話せない場面でテキスト宣言したか。
    var isVoiceless: Bool = false
    /// 宣言を録ったセッション。短縮版の朝フローは昼・夜からも始まる。
    var sessionType: SessionType = .morning
    var createdAt: Date = .now
}

struct VoiceEntryDraft: Sendable {
    var id: UUID = UUID()
    var recordedAt: Date = .now
    var sessionType: SessionType
    var kind: VoiceEntryKind
    var audioPath: String?
    var transcript: String = ""
    var durationSec: Double = 0
    var commitmentID: UUID?
}

enum RepositoryError: Error, Equatable {
    /// 同じ日に 2 件目の `Commitment` を作ろうとした（実装計画 §10 の制約）。
    case commitmentAlreadyExists(dayKey: String)
    case commitmentNotFound(id: UUID)
    case voiceEntryNotFound(id: UUID)
}

// MARK: - Repository

/// SwiftData への出入り口（実装計画 §10）。
///
/// `@ModelActor` にしているので `ModelContext` はこのアクターに閉じる。
/// 返り値は必ずスナップショット（値型）にして、`@Model` のインスタンスを外へ出さない。
@ModelActor
actor Repository {
    /// テストは一時ディレクトリの `AudioFileStore` を差し込む。
    private var injectedAudioFileStore: AudioFileStore?

    func configure(audioFileStore: AudioFileStore) {
        injectedAudioFileStore = audioFileStore
    }

    private func audioFileStore() throws -> AudioFileStore {
        if let injectedAudioFileStore { return injectedAudioFileStore }
        let store = try AudioFileStore.applicationSupport()
        injectedAudioFileStore = store
        return store
    }

    // MARK: 宣言

    /// その日の宣言。無ければ nil。
    func todayCommitment(on date: Date = .now, calendar: Calendar = .current) throws -> CommitmentSnapshot? {
        let key = DayKey.make(from: date, calendar: calendar)
        return try commitmentModel(forDayKey: key).map(snapshot(of:))
    }

    func commitment(id: UUID) throws -> CommitmentSnapshot? {
        try commitmentModel(id: id).map(snapshot(of:))
    }

    /// その日の宣言を作る。同じ `dayKey` に 2 件目は作らせない（実装計画 §10 の制約）。
    ///
    /// 宣言音声がある場合は、同じファイルを指す `VoiceEntry(kind: .declaration)` も同時に作る。
    /// 録音は 1 回だけで、`Commitment.declarationAudioPath` と `VoiceEntry.audioPath` は
    /// 常に同一ファイルを指す。
    @discardableResult
    func createCommitment(_ draft: CommitmentDraft, calendar: Calendar = .current) throws -> CommitmentSnapshot {
        let dayKey = DayKey.make(from: draft.createdAt, calendar: calendar)
        if try commitmentModel(forDayKey: dayKey) != nil {
            throw RepositoryError.commitmentAlreadyExists(dayKey: dayKey)
        }

        let item = try avoidanceItem(title: draft.avoidanceTitle, domain: draft.domain, at: draft.createdAt)
        let commitment = Commitment(
            id: draft.id,
            dayKey: dayKey,
            microAction: draft.microAction,
            plannedAt: draft.plannedAt,
            plannedPlace: draft.plannedPlace,
            declarationAudioPath: draft.declarationAudioPath,
            declarationTranscript: draft.declarationTranscript,
            isVoiceless: draft.isVoiceless,
            outcome: .pending,
            reason: draft.reason,
            createdAt: draft.createdAt
        )
        commitment.avoidanceItem = item
        modelContext.insert(commitment)

        if let audioPath = draft.declarationAudioPath {
            let entry = VoiceEntry(
                recordedAt: draft.createdAt,
                sessionType: draft.sessionType,
                kind: .declaration,
                audioPath: audioPath,
                transcript: draft.declarationTranscript,
                durationSec: draft.declarationDurationSec
            )
            entry.commitment = commitment
            modelContext.insert(entry)
        }

        try modelContext.save()
        return snapshot(of: commitment)
    }

    /// 昼 N1 の結果を書く。`partial` も前進として扱う（企画原則 §22-7）。
    @discardableResult
    func updateOutcome(
        commitmentID: UUID,
        outcome: CommitmentOutcome,
        progressNote: String? = nil,
        at date: Date = .now
    ) throws -> CommitmentSnapshot {
        let commitment = try requireCommitment(id: commitmentID)
        commitment.outcome = outcome
        if let progressNote {
            commitment.progressNote = progressNote
        }
        commitment.avoidanceItem?.lastTouchedAt = date
        try modelContext.save()
        return snapshot(of: commitment)
    }

    /// 昼 N3 / 夜 E0 の「もっと小さく」。`shrinkCount` が 1 増える。
    @discardableResult
    func shrink(
        commitmentID: UUID,
        to text: String,
        estimatedMinutes: Int = 5,
        at date: Date = .now
    ) throws -> CommitmentSnapshot {
        let commitment = try requireCommitment(id: commitmentID)
        commitment.microAction = commitment.microAction.shrunk(to: text, estimatedMinutes: estimatedMinutes)
        commitment.avoidanceItem?.lastTouchedAt = date
        try modelContext.save()
        return snapshot(of: commitment)
    }

    // MARK: 音声

    @discardableResult
    func appendVoiceEntry(_ draft: VoiceEntryDraft) throws -> VoiceEntrySnapshot {
        let entry = VoiceEntry(
            id: draft.id,
            recordedAt: draft.recordedAt,
            sessionType: draft.sessionType,
            kind: draft.kind,
            audioPath: draft.audioPath,
            transcript: draft.transcript,
            durationSec: draft.durationSec
        )
        if let commitmentID = draft.commitmentID {
            entry.commitment = try requireCommitment(id: commitmentID)
        }
        modelContext.insert(entry)
        try modelContext.save()
        return snapshot(of: entry)
    }

    /// その日の音声を古い順に返す。
    func entries(for day: Date, calendar: Calendar = .current) throws -> [VoiceEntrySnapshot] {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let descriptor = FetchDescriptor<VoiceEntry>(
            predicate: #Predicate<VoiceEntry> { $0.recordedAt >= start && $0.recordedAt < end },
            sortBy: [SortDescriptor(\.recordedAt, order: .forward)]
        )
        return try modelContext.fetch(descriptor).map(snapshot(of:))
    }

    /// 最後に声を残した日時。再入場（空白のあとの起動）の判定に使う。
    func lastEntryDate() throws -> Date? {
        var descriptor = FetchDescriptor<VoiceEntry>(
            sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.recordedAt
    }

    /// 音声 1 件を消し、参照が無くなったファイルも消す（実装計画 §10 の削除連動）。
    func deleteVoiceEntry(id: UUID) throws {
        let entry = try requireVoiceEntry(id: id)
        let audioPath: String? = entry.audioPath

        // 宣言音声なら Commitment 側の参照も外す（同じファイルを指しているため）。
        if audioPath != nil {
            let commitments = try modelContext.fetch(
                FetchDescriptor<Commitment>(
                    predicate: #Predicate<Commitment> { $0.declarationAudioPath == audioPath }
                )
            )
            for commitment in commitments {
                commitment.declarationAudioPath = nil
            }
        }

        modelContext.delete(entry)
        try modelContext.save()

        guard let audioPath else { return }
        let remaining = try modelContext.fetch(
            FetchDescriptor<VoiceEntry>(
                predicate: #Predicate<VoiceEntry> { $0.audioPath == audioPath }
            )
        )
        guard remaining.isEmpty else { return }
        try audioFileStore().delete(relativePath: audioPath)
    }

    /// `VoiceEntry` を持たない音声ファイルを消す。起動時に 1 回だけ呼ぶ（実装計画 §10）。
    /// 録音中のファイルを巻き込まないよう、会話中は呼ばない。
    @discardableResult
    func sweepOrphanAudioFiles() throws -> [String] {
        let entries = try modelContext.fetch(FetchDescriptor<VoiceEntry>())
        let live = Set(entries.compactMap(\.audioPath))
        return try audioFileStore().removeOrphans(keeping: live)
    }

    // MARK: 会話の記録

    /// 会話の開始を `SessionLog` に残し、その id を返す（実装計画 §10 / fix-decisions P1.3）。
    ///
    /// task_008 では `SessionViewModel.swift` の `extension Repository` に置いていたものを、
    /// 統合判断 D8 でここへ移した（挙動は変えていない）。
    func startSessionLog(sessionType: SessionType, startedAt: Date, tier: DialogueTier) throws -> UUID {
        let log = SessionLog(sessionType: sessionType, startedAt: startedAt, tier: tier)
        modelContext.insert(log)
        try modelContext.save()
        return log.id
    }

    /// 会話の終わりを書き足す。開始の記録が無ければ何もしない（会話を止めない）。
    func finishSessionLog(
        id: UUID,
        endedAt: Date,
        completed: Bool,
        lastStep: FlowStep?,
        guardrailReplacedCount: Int
    ) throws {
        var descriptor = FetchDescriptor<SessionLog>(predicate: #Predicate<SessionLog> { $0.id == id })
        descriptor.fetchLimit = 1
        guard let log = try modelContext.fetch(descriptor).first else { return }
        log.endedAt = endedAt
        log.completed = completed
        log.lastStep = lastStep
        log.guardrailReplacedCount = guardrailReplacedCount
        try modelContext.save()
    }

    // MARK: 引き継ぎ

    /// その日の朝に渡す引き継ぎ。無ければ nil。
    func carryover(for day: Date, calendar: Calendar = .current) throws -> CarryoverSnapshot? {
        let key = DayKey.make(from: day, calendar: calendar)
        var descriptor = FetchDescriptor<Carryover>(
            predicate: #Predicate<Carryover> { $0.forDayKey == key },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.map(snapshot(of:))
    }

    /// 夜 E1 で作る引き継ぎ。同じ日のものがあれば上書きする。
    @discardableResult
    func saveCarryover(
        forDay day: Date,
        text: String,
        sourceEntryID: UUID? = nil,
        at date: Date = .now,
        calendar: Calendar = .current
    ) throws -> CarryoverSnapshot {
        let key = DayKey.make(from: day, calendar: calendar)
        let existing = try modelContext.fetch(
            FetchDescriptor<Carryover>(predicate: #Predicate<Carryover> { $0.forDayKey == key })
        )
        for item in existing {
            modelContext.delete(item)
        }
        let carryover = Carryover(forDayKey: key, text: text, sourceEntryID: sourceEntryID, createdAt: date)
        modelContext.insert(carryover)
        try modelContext.save()
        return snapshot(of: carryover)
    }

    // MARK: 週次集計

    /// 週次分析の集計（実装計画 §7.6、fix-decisions P2.2）。
    ///
    /// 分野別の件数と理由別の割合だけを出す。結果内訳や平均縮小回数は入れない。
    /// 理由の割合の母数は「理由が付いている宣言」の件数（`reason != nil`）。
    /// 理由を聞かない短縮版の朝フローで割合が薄まらないようにするため。
    func weeklyStats(from start: Date, to end: Date) throws -> WeeklyStats {
        let descriptor = FetchDescriptor<Commitment>(
            predicate: #Predicate<Commitment> { $0.createdAt >= start && $0.createdAt < end }
        )
        let commitments = try modelContext.fetch(descriptor)

        var domainCounts: [TaskDomain: Int] = [:]
        var reasonCounts: [ReasonCategory: Int] = [:]
        var reasonTotal = 0

        for commitment in commitments {
            domainCounts[commitment.avoidanceItem?.domain ?? .other, default: 0] += 1
            if let reason = commitment.reason {
                reasonCounts[reason, default: 0] += 1
                reasonTotal += 1
            }
        }

        var reasonRatios: [ReasonCategory: Double] = [:]
        if reasonTotal > 0 {
            for (reason, count) in reasonCounts {
                reasonRatios[reason] = Double(count) / Double(reasonTotal)
            }
        }

        return WeeklyStats(weekStart: start, domainCounts: domainCounts, reasonRatios: reasonRatios)
    }

    // MARK: 全削除

    /// 「データを全部消す」の結果（task_019）。件数は消す前に数えたもの。
    struct DeletionSummary: Sendable, Equatable {
        var avoidanceItemCount: Int
        var commitmentCount: Int
        var voiceEntryCount: Int
        var sessionLogCount: Int
        var carryoverCount: Int
        /// 消した音声ファイルの数。
        var audioFileCount: Int

        var totalRecordCount: Int {
            avoidanceItemCount + commitmentCount + voiceEntryCount + sessionLogCount + carryoverCount
        }
    }

    /// 全レコードと音声の置き場所ごと消す（task_019）。
    ///
    /// 保留中の通知の取り消しは `cancelPendingNotifications` に委譲する。
    /// `Repository` が `UserNotifications` を持つと、保存データのテストが通知センターを
    /// 要るようになるため（通知の登録と取り消しは task_009 の `NotificationScheduler` の担当）。
    /// `UserDefaults`（`AppSettings.reset()`）もここでは呼ばない。設定を初期値へ戻すかは
    /// 画面の判断であって、保存データの担当ではないから。
    ///
    /// レコードを消したあとで音声の削除に失敗しても、残るのは参照の無いファイルだけで、
    /// 次の起動の `sweepOrphanAudioFiles()` が消す。
    @discardableResult
    func deleteAll(cancelPendingNotifications: @Sendable () -> Void = {}) throws -> DeletionSummary {
        let avoidanceItems = try modelContext.fetch(FetchDescriptor<AvoidanceItem>())
        let commitments = try modelContext.fetch(FetchDescriptor<Commitment>())
        let voiceEntries = try modelContext.fetch(FetchDescriptor<VoiceEntry>())
        let sessionLogs = try modelContext.fetch(FetchDescriptor<SessionLog>())
        let carryovers = try modelContext.fetch(FetchDescriptor<Carryover>())

        let store = try audioFileStore()
        let audioPaths = try store.allRelativePaths()

        let summary = DeletionSummary(
            avoidanceItemCount: avoidanceItems.count,
            commitmentCount: commitments.count,
            voiceEntryCount: voiceEntries.count,
            sessionLogCount: sessionLogs.count,
            carryoverCount: carryovers.count,
            audioFileCount: audioPaths.count
        )

        // 音声から先に消す。`VoiceEntry` を消してから `Commitment` を消すのは、
        // 宣言音声の参照（同一ファイル）を先に外して孤児判定を単純にするため。
        for entry in voiceEntries {
            modelContext.delete(entry)
        }
        for commitment in commitments {
            modelContext.delete(commitment)
        }
        for item in avoidanceItems {
            modelContext.delete(item)
        }
        for log in sessionLogs {
            modelContext.delete(log)
        }
        for carryover in carryovers {
            modelContext.delete(carryover)
        }
        try modelContext.save()

        // 置き場所ごと消す。空の年月フォルダも残さない。
        // 次の録音で `AudioFileStore.allocate` が保護属性つきで作り直す。
        try store.removeOrphans(keeping: [])
        if FileManager.default.fileExists(atPath: store.rootDirectory.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: store.rootDirectory)
        }

        cancelPendingNotifications()
        return summary
    }

    // MARK: - 内部（フェッチ）

    private func commitmentModel(forDayKey key: String) throws -> Commitment? {
        var descriptor = FetchDescriptor<Commitment>(
            predicate: #Predicate<Commitment> { $0.dayKey == key },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func commitmentModel(id: UUID) throws -> Commitment? {
        var descriptor = FetchDescriptor<Commitment>(predicate: #Predicate<Commitment> { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func requireCommitment(id: UUID) throws -> Commitment {
        guard let commitment = try commitmentModel(id: id) else {
            throw RepositoryError.commitmentNotFound(id: id)
        }
        return commitment
    }

    private func requireVoiceEntry(id: UUID) throws -> VoiceEntry {
        var descriptor = FetchDescriptor<VoiceEntry>(predicate: #Predicate<VoiceEntry> { $0.id == id })
        descriptor.fetchLimit = 1
        guard let entry = try modelContext.fetch(descriptor).first else {
            throw RepositoryError.voiceEntryNotFound(id: id)
        }
        return entry
    }

    /// 同じ言葉の対象が生きていれば使い回し、無ければ作る。
    private func avoidanceItem(title: String, domain: TaskDomain, at date: Date) throws -> AvoidanceItem {
        let openRawValue = AvoidanceStatus.open.rawValue
        let carriedOverRawValue = AvoidanceStatus.carriedOver.rawValue
        var descriptor = FetchDescriptor<AvoidanceItem>(
            predicate: #Predicate<AvoidanceItem> {
                $0.title == title
                    && ($0.statusRawValue == openRawValue || $0.statusRawValue == carriedOverRawValue)
            },
            sortBy: [SortDescriptor(\.lastTouchedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        if let existing = try modelContext.fetch(descriptor).first {
            existing.lastTouchedAt = date
            existing.domain = domain
            existing.status = .open
            return existing
        }

        let created = AvoidanceItem(title: title, domain: domain, createdAt: date)
        modelContext.insert(created)
        return created
    }

    // MARK: - 内部（スナップショット）

    private func snapshot(of commitment: Commitment) -> CommitmentSnapshot {
        CommitmentSnapshot(
            id: commitment.id,
            dayKey: commitment.dayKey,
            microAction: commitment.microAction,
            plannedAt: commitment.plannedAt,
            plannedPlace: commitment.plannedPlace,
            declarationAudioPath: commitment.declarationAudioPath,
            declarationTranscript: commitment.declarationTranscript,
            isVoiceless: commitment.isVoiceless,
            outcome: commitment.outcome,
            reason: commitment.reason,
            progressNote: commitment.progressNote,
            createdAt: commitment.createdAt,
            avoidanceID: commitment.avoidanceItem?.id,
            avoidanceTitle: commitment.avoidanceItem?.title ?? "",
            domain: commitment.avoidanceItem?.domain ?? .other
        )
    }

    private func snapshot(of entry: VoiceEntry) -> VoiceEntrySnapshot {
        VoiceEntrySnapshot(
            id: entry.id,
            recordedAt: entry.recordedAt,
            sessionType: entry.sessionType,
            kind: entry.kind,
            audioPath: entry.audioPath,
            transcript: entry.transcript,
            durationSec: entry.durationSec,
            commitmentID: entry.commitment?.id
        )
    }

    private func snapshot(of carryover: Carryover) -> CarryoverSnapshot {
        CarryoverSnapshot(
            id: carryover.id,
            forDayKey: carryover.forDayKey,
            text: carryover.text,
            sourceEntryID: carryover.sourceEntryID,
            createdAt: carryover.createdAt
        )
    }
}
