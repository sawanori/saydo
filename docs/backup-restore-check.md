# バックアップ復元の確認（task_019）

書き出した zip・全削除・iCloud バックアップからの復元を、**人間が実機で**確かめるための手順と記入欄。

- 実施時期: `docs/dogfood/week1.md`（task_013b）の 7 日間ドッグフーディングで実データが溜まった**後**。
  データが 0 件の状態で復元テストをしても、音声が復元されるかは分からない。
- 対象コード: `App/Features/Settings/DataExporter.swift`、`App/Data/Repository.swift` の `deleteAll(cancelPendingNotifications:)`、`App/Data/AudioFileStore.swift`
- 前提: 実装計画 §6-4 / §10、fix-decisions P4.8 / P3.8

エージェントは実機・iCloud・TestFlight を操作できない。**この文書の記入欄は人間が埋める。**
埋まっていない欄がある間、task_019 の `done_definition` は満たされていない。

---

## 0. 何がどこに保存されるか

| 中身 | 置き場所 | iCloud バックアップ |
|---|---|---|
| SwiftData のストア（5 モデル） | `Application Support/default.store`（`SaydoModelContainer` の既定） | 含まれる |
| 音声ファイル | `Application Support/Saydo/Audio/yyyy/MM/<uuid>.m4a` | 含まれる |
| 設定（通知時刻・オンボーディング完了など） | `UserDefaults`（`AppSettings`） | 含まれる |
| 書き出した zip | `tmp/SaydoExport/saydo-export-yyyyMMdd-HHmmss.zip` | **含まれない**（`tmp` はバックアップ対象外。共有したら消えてよい一時ファイル） |

- 音声には `isExcludedFromBackup` を付けていない（実装計画 §6-4 の判断。声そのものが記録なので、機種変更で消えてはいけない）。
- ファイル保護は `completeUntilFirstUserAuthentication`。通知タップ直後（端末ロック中）に宣言音声を再生する必要があるため、`complete` にはしない（実装計画 §7.1）。

---

## 1. 書き出した zip の確認

### 手順

1. 設定画面の「データを書き出す」から ShareLink で zip を Mac へ送る（AirDrop / メール / ファイル）。
2. Mac で展開し、次の形になっていることを見る。

```
saydo-export/
  saydo-export.json          全レコード（5 モデル）
  Audio/
    2026/09/<uuid>.m4a       音声。JSON の audioPath と同じ相対パス
    ...
```

3. `saydo-export.json` を開き、`avoidanceItems` / `commitments` / `voiceEntries` / `sessionLogs` / `carryovers` の 5 つが揃っていることを見る。
4. `Audio/` の m4a を QuickTime で再生し、自分の声が入っていることを確かめる。
5. `voiceEntries[].audioPath` と `commitments[].declarationAudioPath` が同じ値を指している宣言について、`Audio/` にファイルが **1 つだけ** あることを見る（同じ録音を二重に入れない）。

### 記入欄

| 項目 | 記入 |
|---|---|
| 実施日 | |
| 端末 / iOS 版 | |
| アプリ版（`saydo-export.json` の `appVersion`） | |
| zip のファイル名 | |
| zip のサイズ | |
| JSON の 5 コレクションが揃っていたか | |
| 音声の件数（`Audio/` の m4a 数） | |
| 音声が再生できたか | |
| 気づいたこと | |

---

## 2. 容量の実測と見積もりの突き合わせ

見積もり（実装計画 §10、fix-decisions P4.8）:

- AAC 32 kbps モノラル × 15 秒 = 32,000 bit/s × 15 s = 480,000 bit = **約 60 KB/件**
- 1 日 5 件 = **約 300 KB/日**
- 365 日 = 約 109.5 MB = **年間約 110 MB**

### 手順

1. 展開した `saydo-export/Audio` で `find . -name '*.m4a' | wc -l` と `du -sk Audio` を実行する。
2. 合計バイト ÷ 件数で 1 件あたりを出し、下の表に書く。
3. 1 日あたりの件数（ドッグフーディング 7 日の実測）から年間を出し、110 MB と比べる。
4. 見積もりから 2 倍以上ずれていたら、実装計画 §10 と本書の数値を実測に合わせて直す（直したことをここに書く）。

### 記入欄

| 項目 | 見積もり | 実測 |
|---|---|---|
| 1 件あたりの音声サイズ | 約 60 KB | |
| 1 日あたりの録音件数 | 5 件 | |
| 1 日あたりの容量 | 約 300 KB | |
| 年間の容量 | 約 110 MB | |
| 7 日間の実測合計 | — | |
| 見積もりの訂正が要るか | — | |

---

## 3. 全削除の確認

`Repository.deleteAll(cancelPendingNotifications:)` が消すもの:

- SwiftData の 5 モデル全レコード
- 音声の置き場所（`Application Support/Saydo/Audio` をディレクトリごと）

**消さないもの**（画面側の責任。設定画面が `deleteAll` と一緒に呼ぶ）:

- `UserDefaults` の設定 → `AppSettings.reset()`。これを呼ばないとオンボーディングに戻らない
  （`hasCompletedOnboarding` が true のまま残る）。
- 保留中の通知 → `deleteAll` の `cancelPendingNotifications` コールバックに渡す
  （`UNUserNotificationCenter.current().removeAllPendingNotificationRequests()`）。
  `Repository` は `UserNotifications` に依存しない。

### 手順

1. データがある状態で「データを全部消す」を実行する。
2. アプリを一度落として再起動し、オンボーディングに戻ることを見る。
3. Timeline が空になっていることを見る。
4. 通知設定の一覧（または翌日）で、保留中の通知が残っていないことを見る。
5. 全削除の直後にもう一度書き出しを実行し、zip の JSON が空（5 コレクションとも 0 件）で音声が 0 件であることを見る。

### 記入欄

| 項目 | 記入 |
|---|---|
| 実施日 | |
| 再起動後にオンボーディングへ戻ったか | |
| Timeline が空になったか | |
| 保留中の通知が消えたか | |
| 全削除後の書き出しが空だったか | |
| 気づいたこと | |

---

## 4. iCloud バックアップからの復元

**ここが task_019 の本体。** 7 日分のデータが入った状態で行う。

### 手順

1. 設定 → Apple ID → iCloud → iCloud バックアップ が**オン**であることを確かめ、「今すぐバックアップを作成」を実行して完了まで待つ。
2. 念のため、直前に第 1 節の書き出しをして zip を Mac に保存しておく（復元が失敗しても声を失わないため）。
3. SAYDO を削除する。
4. 端末を初期化し、iCloud バックアップから復元する。
   - 端末を初期化できない場合は、**別の端末**にバックアップから復元してもよい。その場合はどちらでやったかを記入欄に書く。
5. 復元後に SAYDO を開き、次を見る。
   - オンボーディングに戻らず、7 日分の Timeline がそのまま出ること
   - Timeline の音声を再生でき、自分の声が鳴ること（**相対パスで解決できているかの確認**。アプリコンテナの UUID は復元で変わる）
   - 昼の通知から宣言音声の再生カードが出て、音が鳴ること
6. 音声が鳴らなかった場合は、鳴らなかったエントリの日時と、そのときの画面表示をそのまま記入欄に書く。

### 記入欄

| 項目 | 記入 |
|---|---|
| 実施日 | |
| バックアップ作成日時 | |
| 復元方法（同一端末の初期化 / 別端末） | |
| 端末 / iOS 版（復元先） | |
| 復元後のレコード件数（Timeline の日数） | |
| 音声が再生できたか（件数 / 全件） | |
| 再生できなかったエントリ | |
| 通知からの宣言音声の再生 | |
| 気づいたこと | |

---

## 5. ファイル保護属性の確認

`AudioFileStore` は音声のディレクトリとファイルに `completeUntilFirstUserAuthentication` を付ける。

### 手順（どちらか一方でよい）

- **A. 実機の挙動で見る**: 端末を再起動し、**パスコードを一度も入れないまま**通知をタップして宣言音声が再生されることを確かめる。
  再生できれば `completeUntilFirstUserAuthentication` は効いていない（`complete` なら再生できない）。
  再起動後にパスコードを入れてからなら再生できる、という状態であれば意図どおり。
- **B. Xcode のデバッガで見る**: `po try? FileManager.default.attributesOfItem(atPath: <音声の絶対パス>)[.protectionKey]` を実行し、
  `NSFileProtectionCompleteUntilFirstUserAuthentication` が返ることを見る。

### 記入欄

| 項目 | 記入 |
|---|---|
| 実施日 | |
| 確認方法（A / B） | |
| 結果 | |

---

## 6. バックアップが無効な端末の表示との整合

task_013 でオンボーディングと設定画面に「iCloud バックアップが無効な場合、音声は端末内にしか残りません」という趣旨の文言を入れている（fix-decisions P4.8 / P3.8）。

### 手順

1. 設定 → iCloud バックアップを**オフ**にする。
2. アプリの設定画面を開き、上記の文言が出ることを見る。
3. その文言が、第 4 節の復元結果と食い違っていないことを見る
   （例: 「復元されない」と書いてあるのに復元できた、あるいはその逆）。

### 記入欄

| 項目 | 記入 |
|---|---|
| 実施日 | |
| 表示された文言 | |
| 第 4 節の結果と矛盾しないか | |
| 文言の修正が要るか | |

---

## 7. 現時点で分かっていること（エージェントが確認した範囲）

以下は **macOS 上での実行**で確かめた。iOS シミュレータ・実機では未確認（iOS 26.x のシミュレータランタイムが未導入。`docs/PROGRESS.md` の task_001 参照）。

- `NSFileCoordinator` の `.forUploading` にディレクトリを渡すと zip ができ、
  `saydo-export/saydo-export.json` と `saydo-export/Audio/yyyy/MM/<uuid>.m4a` の相対パスが保たれる。
- 全モデル（`AvoidanceItem` / `Commitment` / `VoiceEntry` / `SessionLog` / `Carryover`）が
  `saydo-export.json` に入り、`ExportArchive` として読み戻せる。列挙は rawValue の文字列で入る。
- 宣言音声（`Commitment.declarationAudioPath` と宣言の `VoiceEntry.audioPath` が同一ファイル）は
  zip に 1 つだけ入る。
- 書き出しのファイル名は西暦で作る（`Calendar.current` は端末の暦設定が和暦だと
  `.year` が元号の年になるため、`Calendar(identifier: .gregorian)` に固定してある）。
- `deleteAll` は 5 モデルを消し、音声の置き場所をディレクトリごと消し、
  渡したコールバックを呼ぶ。実行後に書き出すと 5 コレクションとも 0 件になる。

未確認（この文書の記入欄で埋める）:

- iOS 実機での zip 共有（ShareLink）と Mac での展開
- iCloud バックアップからの復元と、復元後の音声再生
- ファイル保護属性が実機で付いていること
- 実測の 1 件あたり容量と年間見積もり
