import Foundation
import SaydoCore

/// 約束する画面（`PromiseViewModel`）が使う保存操作だけを切り出した契約（実装計画 §17.4）。
///
/// `Repository.swift` 本体には足さない（別のタスクが同じファイルを触っているため）。
/// `Repository` は `@ModelActor` の具象アクターなので、テストで差し替えるためにこの契約を挟む。
protocol PromiseStore: Sendable {
    /// その日の約束を作る。つないだ声（`declarationAudioPath`）があれば、同じファイルを指す
    /// 宣言の `VoiceEntry` も同時に作られる。
    func createCommitment(_ draft: CommitmentDraft) async throws -> CommitmentSnapshot
    func appendVoiceEntry(_ draft: VoiceEntryDraft) async throws -> VoiceEntrySnapshot
}

/// `Repository` を `PromiseStore` として渡すための薄い包み。
///
/// `Repository.createCommitment` は既定引数（`calendar`）を持つので、そのままではプロトコル要件の
/// witness にならない。日付の区切りは画面と同じ暦で決める。
struct RepositoryPromiseStore: PromiseStore {
    let repository: Repository
    let calendar: Calendar

    init(_ repository: Repository, calendar: Calendar = .current) {
        self.repository = repository
        self.calendar = calendar
    }

    func createCommitment(_ draft: CommitmentDraft) async throws -> CommitmentSnapshot {
        try await repository.createCommitment(draft, calendar: calendar)
    }

    func appendVoiceEntry(_ draft: VoiceEntryDraft) async throws -> VoiceEntrySnapshot {
        try await repository.appendVoiceEntry(draft)
    }
}
