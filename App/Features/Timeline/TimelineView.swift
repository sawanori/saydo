import SwiftData
import SwiftUI

/// 記録タブ（実装計画 §8、`docs/design/Timeline.dc.html`）。
///
/// 記録がある日だけを新しい順に並べ、空白日のプレースホルダを置かない（retention-strategy R4）。
/// 「今日は休む」を選んだ日は `Commitment` も `VoiceEntry` も作られない（R3、`AppDelegate.handle(_:)`）ので、
/// 除外の分岐を書かなくてもセクションが立たない。
/// 一覧・チェックボックス・進捗率は作らない（企画原則 §22-8）。編集・削除・検索も持たない。
///
/// 上部の `topAccessory` は統合時に 3 件目の 1 行インサイト（`InsightCardView`）が入る差し込み口。
struct TimelineView<Accessory: View>: View {
    /// 全件を新しい順に。日別の束ね方は `TimelineGrouping` が決める。
    @Query(TimelineQuery.allEntries, animation: .default) private var entries: [VoiceEntry]

    @Environment(\.calendar) private var calendar

    @State private var playback: TimelinePlayback
    private let topAccessory: Accessory

    init(
        player: any Playing,
        audioFileStore: AudioFileStore? = nil,
        @ViewBuilder topAccessory: () -> Accessory
    ) {
        _playback = State(initialValue: TimelinePlayback(player: player, audioFileStore: audioFileStore))
        self.topAccessory = topAccessory()
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: TimelineLayout.blockSpacing) {
                Text(verbatim: "SAYDO")
                    .saydoText(.logo)

                topAccessory

                if sections.isEmpty {
                    Text(TimelineCopy.empty)
                        .saydoText(.list)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(sections) { section in
                        daySection(section)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, TimelineLayout.horizontalPadding)
            .padding(.top, TimelineLayout.topPadding)
            .padding(.bottom, TimelineLayout.bottomPadding)
        }
        .scrollIndicators(.hidden)
        .saydoGround()
        .onDisappear { playback.stop() }
    }

    // MARK: - 部品

    /// 表示用の並べ替えは必ず `TimelineGrouping` を通す（試せる形を 1 か所にまとめるため）。
    private var sections: [DaySection] {
        TimelineGrouping.sections(from: entries.map(TimelineQuery.snapshot(of:)), calendar: calendar)
    }

    private func daySection(_ section: DaySection) -> some View {
        VStack(alignment: .leading, spacing: TimelineLayout.sectionHeaderSpacing) {
            Text(section.date, format: .dateTime.month().day().weekday(.abbreviated))
                .saydoText(.sectionLabel)

            VStack(alignment: .leading, spacing: TimelineLayout.rowSpacing) {
                ForEach(section.entries) { entry in
                    VoiceEntryRow(
                        entry: entry,
                        isPlaying: playback.nowPlayingID == entry.id
                    ) {
                        toggle(entry)
                    }
                }
            }
            .background(alignment: .topLeading) { rail }
        }
    }

    /// マイクを結ぶ縦レール。両端は地に溶ける（design-notes 5.）。
    private var rail: some View {
        LinearGradient(
            stops: [
                .init(color: SaydoTheme.Palette.accent.opacity(0), location: 0),
                .init(color: SaydoTheme.Palette.accent.opacity(0.22), location: 0.18),
                .init(color: SaydoTheme.Palette.accent.opacity(0.22), location: 0.82),
                .init(color: SaydoTheme.Palette.accent.opacity(0), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(width: 1)
        .padding(.vertical, TimelineLayout.railInset)
        .padding(.leading, TimelineLayout.railLeading)
        .accessibilityHidden(true)
    }

    private func toggle(_ entry: VoiceEntrySnapshot) {
        if playback.nowPlayingID == entry.id {
            playback.stop()
        } else {
            playback.play(entry: entry)
        }
    }
}

extension TimelineView where Accessory == EmptyView {
    /// 上部の差し込みが無い形（統合前・プレビュー用）。
    init(player: any Playing, audioFileStore: AudioFileStore? = nil) {
        self.init(player: player, audioFileStore: audioFileStore) { EmptyView() }
    }
}

/// 画面の余白（`docs/design/Timeline.dc.html`）。
/// `TimelineView` が総称型で static な格納プロパティを持てないため、型の外に置く。
private enum TimelineLayout {
    static let horizontalPadding: CGFloat = 30
    static let topPadding: CGFloat = 62
    static let bottomPadding: CGFloat = 40
    static let blockSpacing: CGFloat = 32
    static let sectionHeaderSpacing: CGFloat = 12
    static let rowSpacing: CGFloat = 24
    /// 縦レールの位置と、上下で消える分。
    static let railLeading: CGFloat = 8
    static let railInset: CGFloat = 16
}

// MARK: - 取得と変換

/// `@Query` に渡す取得条件と、表示用の値型への変換。
/// `TimelineView` が総称型なので、型の外に置いて総称引数の推論を要らなくしている。
private enum TimelineQuery {
    /// `recordedAt` 降順で全件。`commitment` を先読みするのは、行を作るたびに
    /// リレーションのフォールトが起きるのを避けるため（スクロールのなめらかさ）。
    static var allEntries: FetchDescriptor<VoiceEntry> {
        var descriptor = FetchDescriptor<VoiceEntry>(
            sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]
        )
        descriptor.relationshipKeyPathsForPrefetching = [\.commitment]
        return descriptor
    }

    /// `@Model` は Sendable ではないので、表示に使う前に値型へ写す。
    /// `Repository` にある同名の変換と同じ内容だが、あちらは private なので画面側で持つ。
    static func snapshot(of entry: VoiceEntry) -> VoiceEntrySnapshot {
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
}
