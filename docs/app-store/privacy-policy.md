# SAYDO プライバシーポリシー（掲載用全文 / Privacy Policy）

- 作成日: 2026-09-04
- 対象タスク: task_020
- 用途: この文書の §1（日本語）と §2（English）を、そのまま `non-turn.com` 配下の静的ページに掲載し、その URL を App Store Connect の「プライバシーポリシー URL」に登録する。
- 掲載先 URL: `https://non-turn.com/saydo/privacy`（**要確認**: 実際のパスは未確定）
- App Store Connect の「App のプライバシー」の回答: **「このアプリはデータを収集しません」（Data Not Collected）**。本文の内容はこの回答と一致している（§1-4 と §1-11、`metadata.md` §11）。
- 根拠にした設計: `docs/implementation-plan.md` §0.1・§0.2・§6・§7.3・§7.4・§10・§14-11、`docs/task-list.json` task_019、`docs/acceptance-checks.json` check_016。

---

## 1. 日本語（掲載用全文）

### SAYDO プライバシーポリシー

制定日: 2026 年 9 月 4 日
最終改定日: 2026 年 9 月 4 日

NonTurn LLC（以下「当社」）は、iPhone 向けアプリケーション「SAYDO」（以下「本アプリ」）における利用者の情報の取り扱いについて、以下のとおり定めます。

#### 1. はじめに（このポリシーの要点）

本アプリは、利用者の録音と文字起こしを**利用者の iPhone の中にのみ保存**します。当社のサーバーはありません。利用者のアカウントもありません。当社が利用者のデータを受け取ることはなく、閲覧することもできません。

本アプリには、ネットワーク通信を行うプログラムが含まれていません。解析ツール（アナリティクス SDK）、広告、クラッシュレポートの送信機能も組み込んでいません。

#### 2. 事業者の情報

- 事業者名: NonTurn LLC
- ウェブサイト: https://non-turn.com/
- 連絡先: snp.inc.info@gmail.com

#### 3. 本アプリが端末内に保存する情報

本アプリは、利用者が本アプリを使う中で、次の情報を利用者の端末内に作成し保存します。いずれも当社へは送信されません。

| 種類 | 内容 | 保存場所 |
|---|---|---|
| 録音した音声 | 利用者が話した音声（逃げたいこと、その理由、自分への宣言、状態、止めているもの、今日の前進、明日の予定） | 端末内のアプリ領域（音声ファイル） |
| 文字起こしテキスト | 上記の音声を端末内で文字にしたもの | 端末内のデータベース |
| 会話の記録 | 逃げたいこととその分野、理由の分類、決めた行動の内容、予定した時刻と場所、その日の結果、行動を小さくした回数 | 端末内のデータベース |
| セッションの記録 | 各回の開始時刻・終了時刻・完了したかどうか・どこまで進んだか | 端末内のデータベース |
| 設定 | 通知の時刻と回数、週末を休む設定、一人になれる時刻、読み上げ音声の選択、無音と判断する秒数 | 端末内の設定領域 |

本アプリは、次の情報を**取得しません**。

- 氏名、メールアドレス、電話番号、生年月日その他の登録情報（アカウント機能がありません）
- 位置情報（位置情報の機能を使用しません。会話の中で利用者が話した「どこでやるか」は、利用者自身の言葉のテキストとして端末内に残るだけです）
- 連絡先、写真、カレンダー、ヘルスケアのデータ
- 広告識別子（IDFA）その他のトラッキング用の識別子
- 他のアプリの利用状況

#### 4. 外部への送信について

本アプリは、利用者の録音、文字起こし、会話の記録、設定を、当社のサーバーその他の外部へ**送信しません**。第三者に提供・販売することもありません。

本アプリにはネットワーク通信のプログラムが含まれていないため、これは運用上の方針ではなく、アプリの作りとして送信できない状態です。

#### 5. マイクの利用について

本アプリはマイクを次の目的でのみ使用します。

- 利用者が今日逃げたいことと、その理由、そして自分への宣言を、利用者自身の声で記録するため
- 記録した宣言を、利用者が決めた時刻に利用者自身へ再生するため

録音が始まる条件は次の 2 つに限られます。

1. 利用者が本アプリの通知をタップして会話に入ったとき
2. 利用者が本アプリの画面から自分で会話を始めたとき

いずれの場合も、録音はアプリの質問の読み上げが終わってから始まります。マイクが音を聞いている間は、画面中央に音の大きさに応じた波形が表示され続けます。一定時間（既定 1.5 秒。設定で変更可）沈黙すると自動的に止まります。

本アプリは、上記以外の場面でマイクを使用しません。アプリを閉じている間や、バックグラウンドにある間に録音することはありません。

マイクの利用を許可しない設定のままでも、本アプリは文字入力だけで最後まで利用できます。

#### 6. 音声認識（文字起こし）について

文字起こしは、iOS が端末内で行う音声認識の仕組み（`SpeechAnalyzer`）を使用します。**利用者の音声が音声認識のために外部へ送信されることはありません。**

なお、日本語の音声認識に必要なモデルデータ、および読み上げに使う高品質な音声データは、iOS の仕組みによって Apple から端末へダウンロードされることがあります。これは OS が行うデータの取得であり、利用者の録音や発話の内容が送信されるものではありません。

#### 7. 端末内の AI 処理について

Apple Intelligence が利用できる端末では、追加の質問や行動の分解に、端末内で動作する Apple の言語モデル（Foundation Models）を使用します。**この処理は端末の中で完結し、利用者の言葉が外部へ送信されることはありません。**

週ごとのふりかえり文を作る際も、モデルに渡すのは集計した件数と割合だけで、録音や文字起こしの原文は渡しません。

Apple Intelligence に対応していない端末では、この処理を行わず、あらかじめ用意された文面で同じ会話が進みます。機能の差については App Store の説明文に記載しています。

#### 8. 通知について

本アプリの通知は、すべて端末内で予定されるローカル通知です。当社のサーバーから送るプッシュ通知ではありません。通知のために利用者の情報を外部へ送ることはありません。

#### 9. バックアップについて

端末内に保存された本アプリのデータ（音声ファイルとデータベース）は、iOS の端末バックアップの対象に含まれます。iCloud バックアップを有効にしている場合、これらのデータは Apple の iCloud に保存され、その取り扱いは Apple のプライバシーポリシーに従います。当社がそのバックアップにアクセスすることはできません。

iCloud バックアップを無効にしている場合、本アプリのデータは端末内にのみ存在します。端末を紛失・初期化した場合、データを復元する手段はありません。本アプリはこの点を、初回設定時と設定画面に表示します。

#### 10. データの保存期間と削除の方法

保存した情報は、利用者が削除するまで端末内に残ります。当社が保存期間を定めて自動的に削除することはありません。

削除の方法は次のとおりです。

1. **アプリ内でまとめて削除する**: 設定画面の「すべてのデータを削除」を選ぶと、端末内の記録と音声ファイルがすべて削除され、予定されていた通知も解除されます。削除したデータは元に戻せません。
2. **アプリを削除する**: iPhone から本アプリを削除すると、アプリ内に保存されていたデータも端末から削除されます。
3. **iCloud バックアップからも消す**: 上記 1 または 2 のあと、iOS の「設定」→ Apple アカウント →「iCloud」→「バックアップ」から、当該端末のバックアップを削除するか、次回のバックアップで反映させます。

削除の前にデータを手元に残したい場合は、設定画面の「データを書き出す」から、音声ファイルと記録（JSON 形式）をまとめた ZIP ファイルを書き出せます。書き出したファイルの保存先と共有先は、利用者自身が iOS の共有機能で選びます。当社はその内容を受け取りません。

#### 11. App Store の「データを収集しない」表示について

App Store の本アプリのページには「データを収集しない」と表示されます。これは本ポリシーの §3・§4 のとおり、当社が利用者の情報を一切受け取っていないためです。端末内に保存される情報は、利用者の端末の中にとどまります。

#### 12. お子様の利用について

本アプリは、13 歳未満のお子様に向けて設計・提供しているものではありません。本アプリはアカウント登録を求めず、いかなる個人情報も収集しません。

#### 13. 第三者のサービスについて

本アプリは、広告ネットワーク、解析サービス、SNS 連携、外部の生成 AI サービスを一切利用していません。本アプリに組み込まれている外部のソフトウェア部品はありません。

#### 14. 利用者の権利

本アプリは利用者の個人情報を取得していないため、当社に対する開示・訂正・利用停止の請求の対象となるデータを、当社は保有していません。端末内のデータについては、利用者が §10 の方法でいつでも書き出し、削除できます。

#### 15. 本ポリシーの変更

本ポリシーの内容を変更する場合は、本ページを更新し、最終改定日を書き換えます。本アプリの取り扱いに実質的な変更がある場合（たとえば外部への送信を伴う機能を追加する場合）は、その機能を含むバージョンの提供開始前に、本ページとアプリ内で告知します。

#### 16. お問い合わせ

本ポリシーおよび本アプリのデータの取り扱いについてのお問い合わせは、次の連絡先へお願いします。

- NonTurn LLC
- メール: snp.inc.info@gmail.com
- ウェブサイト: https://non-turn.com/

---

## 2. English（掲載用全文 / full text for publication）

### SAYDO Privacy Policy

Effective date: September 4, 2026
Last updated: September 4, 2026

NonTurn LLC ("we", "us") provides the iPhone application "SAYDO" (the "App"). This policy explains how information is handled in the App.

#### 1. Summary

The App stores your recordings and transcripts **only on your iPhone**. We operate no servers for the App. There are no user accounts. We never receive your data and cannot access it.

The App contains no networking code. It includes no analytics SDK, no advertising, and no crash reporting.

#### 2. Who we are

- Company: NonTurn LLC
- Website: https://non-turn.com/
- Contact: snp.inc.info@gmail.com

#### 3. What the App stores on your device

While you use the App, the following is created and stored on your device. None of it is transmitted to us.

| Type | Contents | Where it is stored |
|---|---|---|
| Voice recordings | What you say (what you want to avoid today, why, your spoken commitment to yourself, your status, what is stopping you, what moved forward today, what you plan for tomorrow) | Audio files in the App's container on your device |
| Transcripts | Text produced from those recordings, on your device | On-device database |
| Session records | The item you named, its category, the reason category, the small action you chose, the time and place you planned, the outcome of the day, and how many times the action was made smaller | On-device database |
| Session logs | Start time, end time, whether the session finished, and the step you reached | On-device database |
| Settings | Notification times and count, weekend pause, the time you are alone, the chosen speech voice, and the silence threshold | On-device settings storage |

The App does **not** collect:

- Name, email address, phone number, date of birth, or any registration data (there are no accounts)
- Location data (the App uses no location services; the place you mention in a conversation is only stored as your own words in text)
- Contacts, photos, calendar, or health data
- Advertising identifiers (IDFA) or any tracking identifiers
- Your usage of other apps

#### 4. No transmission to third parties

The App does **not** transmit your recordings, transcripts, session records, or settings to our servers or to anyone else. We do not sell or share them.

Because the App contains no networking code, this is not merely a policy commitment — the App is built without the ability to send this data anywhere.

#### 5. Microphone use

The App uses the microphone only to:

- Record, in your own voice, what you want to avoid today, why, and the commitment you make to yourself
- Play that commitment back to you at the time you chose

Recording begins only in these two situations:

1. You tap a notification from the App and enter a conversation
2. You start a conversation yourself from within the App

In both cases, recording starts only after the App has finished speaking its question aloud. While the microphone is listening, a live waveform is shown on screen for the entire time. Recording stops automatically after a period of silence (1.5 seconds by default, adjustable in Settings).

The App does not use the microphone at any other time. It does not record while it is closed or in the background.

If you decline microphone access, you can still complete every part of the App using text input.

#### 6. Speech recognition

Transcription uses the on-device speech recognition provided by iOS (`SpeechAnalyzer`). **Your audio is not sent anywhere for transcription.**

Note that the Japanese speech recognition model, and the higher-quality speech voices used for reading text aloud, may be downloaded to your device from Apple by iOS itself. That is a download of model data performed by the operating system; it does not send your recordings or the contents of your speech.

#### 7. On-device AI

On devices where Apple Intelligence is available, the App uses Apple's on-device language model (Foundation Models) to phrase a follow-up question and to help break an action into smaller steps. **This processing happens entirely on the device; your words are not transmitted.**

When the App composes the weekly reflection sentence, it passes only aggregate counts and percentages to the model — never the original recordings or transcripts.

On devices without Apple Intelligence, this processing does not occur and the same conversation proceeds using prepared wording. The difference in features is described on the App Store product page.

#### 8. Notifications

All notifications are local notifications scheduled on your device. They are not push notifications sent from a server of ours. No information leaves your device in order to deliver them.

#### 9. Backups

The App's on-device data (audio files and database) is included in the iOS device backup. If you have iCloud Backup enabled, this data is stored in Apple's iCloud and is handled according to Apple's privacy policy. We cannot access that backup.

If iCloud Backup is disabled, the App's data exists only on your device. If the device is lost or erased, there is no way to recover it. The App states this during first-time setup and in Settings.

#### 10. Retention and deletion

Stored information remains on your device until you delete it. We do not apply any retention period or delete it for you.

You can delete it as follows:

1. **Delete everything inside the App**: choose "Delete all data" in Settings. All records and audio files on the device are deleted and any scheduled notifications are cancelled. This cannot be undone.
2. **Delete the App**: removing the App from your iPhone also removes the data stored inside it.
3. **Remove it from iCloud Backup as well**: after step 1 or 2, go to iOS Settings → your Apple Account → iCloud → Backup, and delete the backup for that device or let the next backup replace it.

If you want a copy before deleting, use "Export data" in Settings to produce a ZIP file containing your audio files and records (JSON). You choose where it goes using the iOS share sheet. We do not receive it.

#### 11. About the "Data Not Collected" label on the App Store

The App's App Store page shows "Data Not Collected". This reflects sections 3 and 4 above: we receive no information from you whatsoever. Information stored on your device stays on your device.

#### 12. Children

The App is not designed for or directed at children under 13. It requires no account and collects no personal information.

#### 13. Third-party services

The App uses no advertising networks, no analytics services, no social network integrations, and no external generative AI services. It embeds no third-party software components.

#### 14. Your rights

Because we hold no personal information about you, we have no data subject to a request for disclosure, correction, or suspension of use. For the data on your device, you can export it or delete it at any time using the methods in section 10.

#### 15. Changes to this policy

If we change this policy, we will update this page and revise the "Last updated" date. If there is a substantive change to how the App handles data — for example, adding a feature that transmits data externally — we will announce it on this page and inside the App before releasing the version containing it.

#### 16. Contact

For questions about this policy or about how the App handles data:

- NonTurn LLC
- Email: snp.inc.info@gmail.com
- Website: https://non-turn.com/

---

## 3. 掲載時の注意（この節は掲載しない）

1. 掲載ページは、Apple の要件により**アプリのインストールやログインなしで誰でも読める公開ページ**である必要がある。会員限定・noindex 付きの下書きページに置かない。
2. 日本語と英語を同一ページの上下に並べるか、言語切り替えの 2 ページにするかは自由。App Store Connect には日本語ページの URL を登録する（**要確認**: 販売地域を全世界にする場合は英語ページも到達できるようにする）。
3. 「最終改定日」はページ上部に必ず表示する。改定のたびに書き換える。
4. 本文中の §10-1「すべてのデータを削除」と「データを書き出す」は、task_019（`DataExporter`）で実装される設定画面の項目名である。**実装時の実際のボタン名と文言を一致させること。** ボタン名が変わったらこのポリシーも直す。
5. §5 の「既定 1.5 秒。設定で変更可」は implementation-plan §7.3 の値（1.2 / 1.5 / 2.0 秒）に基づく。実装で既定値が変わったらこの記述も直す。
6. 本アプリは個人情報を取得しないため、日本の個人情報保護法上の「個人情報取扱事業者」としての公表事項（利用目的の公表、開示等の請求手続）を本アプリについて掲げる必要は生じない想定でいる。**要確認**: 会社サイト全体のプライバシーポリシー（問い合わせフォーム等を含む）と本アプリ用ポリシーの関係を整理し、二重に矛盾しないようにする。必要なら「本ポリシーは SAYDO についてのみ適用される」旨の一文を冒頭に足す。

## 4. 要確認事項

1. 掲載 URL の確定（`https://non-turn.com/saydo/privacy` は案）。
2. 会社全体のプライバシーポリシーとの関係（適用範囲を明記する一文を足すか）。
3. 英語ページを公開するか（販売地域の決定に連動）。
4. 設定画面の実際のボタン名（「すべてのデータを削除」「データを書き出す」）が task_019 の実装と一致するか。
5. 個別の記録を 1 件ずつ削除する UI を v1.0.0 で提供するか。提供する場合は §10 に手順を 1 つ追加する（現在の計画では Timeline の個別削除 UI は明示されていない）。
