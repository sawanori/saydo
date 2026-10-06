import SwiftUI
import SaydoCore

/// アプリの外枠（実装計画 §8 / §17.3）。
///
/// `TabView` は「今日」「記録」の 2 タブだけ。設定は「今日」の右上。
/// 起動時・前面に戻ったとき・アラームの「開く」・通知のタップは、どれも `AppRouter.resolveEntry`
/// の同じ判定を通り、約束する画面か答える画面を全画面で被せる（無ければ今日の画面のまま）。
/// 初回だけ `OnboardingView` を出す。
struct RootView: View {

    let router: AppRouter

    @State private var insightModel: InsightViewModel?
    @State private var todayModel: TodayViewModel?
    @State private var isSettingsPresented = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if !router.hasCompletedOnboarding {
                OnboardingView(alarms: router.alarms) {
                    Task { await router.completeOnboarding() }
                }
            } else if router.hasResolvedEntry {
                ZStack {
                    tabs
                        // 被せた画面の下は、読み上げにも操作にも出さない。
                        .accessibilityHidden(router.cover != nil)
                        .allowsHitTesting(router.cover == nil)
                    cover
                }
                .animation(.easeOut(duration: 0.2), value: router.cover?.id)
            } else {
                // 起動して最初の判定が済むまでの 1 フレーム。今日の画面を先に見せない。
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .saydoGround()
            }
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView(
                onTimesChanged: { await router.refreshAlarms() },
                onDataDeleted: { router.reloadOnboardingState() }
            )
        }
        .task(id: router.hasCompletedOnboarding) {
            guard router.hasCompletedOnboarding else { return }
            if todayModel == nil {
                todayModel = router.makeTodayViewModel()
            }
            await router.resolveEntry(openRequested: FollowUpOpenRequest.consume())
            await router.refreshAlarms()
            if insightModel == nil {
                insightModel = InsightViewModel(repository: router.repository)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, router.hasCompletedOnboarding else { return }
            Task {
                await router.resolveEntry(openRequested: FollowUpOpenRequest.consume())
                await insightModel?.load()
                await router.refreshAlarms()
            }
        }
        // アプリが前面にあるときにアラームの「開く」が押された。
        .onReceive(NotificationCenter.default.publisher(for: FollowUpOpenRequest.didRequest)) { _ in
            guard router.hasCompletedOnboarding, FollowUpOpenRequest.consume() else { return }
            Task { await router.resolveEntry(openRequested: true) }
        }
        .onChange(of: router.cover?.id) { _, coverID in
            // 設定を開いたままだと、被せた画面がその下に隠れる。
            if coverID != nil { isSettingsPresented = false }
        }
        .onChange(of: router.generation) { _, _ in
            Task { await insightModel?.load() }
        }
    }

    private var tabs: some View {
        TabView {
            Group {
                if let todayModel {
                    TodayView(
                        viewModel: todayModel,
                        reloadToken: router.generation,
                        // 朝の通知はアラームに置き換えたので、通知の掲示は出さない（§17.9 の 5）。
                        notificationsDenied: false,
                        onOpenPromise: { router.openPromise() },
                        onOpenFollowUp: { commitment in router.openFollowUp(for: commitment) },
                        onOpenSettings: { isSettingsPresented = true }
                    )
                } else {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .saydoGround()
                }
            }
            .tabItem { Text(RootCopy.todayTab) }

            VoiceTimelineView(player: router.sharedPlayer, audioFileStore: router.audioFiles) {
                if let insightModel {
                    InsightCardView(model: insightModel)
                }
            }
            .tabItem { Text(RootCopy.timelineTab) }
        }
        .tint(SaydoTheme.Palette.accent)
    }

    /// 全画面で被せる画面。約束する画面か、答える画面。
    @ViewBuilder
    private var cover: some View {
        switch router.cover {
        case .promise(let token):
            PromiseCover(router: router)
                .id(token)
                .transition(.opacity)
                .zIndex(1)
        case .followUp(let commitment):
            FollowUpCover(router: router, commitment: commitment)
                .id(commitment.id)
                .transition(.opacity)
                .zIndex(1)
        case nil:
            EmptyView()
        }
    }

}

// MARK: - 被せる画面

/// 約束する画面。出た時点でマイクの許可を確かめ（未決定なら 1 回だけ求め）、頭脳を 1 回だけ作る。
private struct PromiseCover: View {

    let router: AppRouter

    private struct Prepared {
        let viewModel: PromiseViewModel
        let microphoneGranted: Bool
    }

    @State private var prepared: Prepared?

    var body: some View {
        Group {
            if let prepared {
                PromiseView(
                    viewModel: prepared.viewModel,
                    microphoneGranted: prepared.microphoneGranted
                ) {
                    Task { await router.closePromise() }
                }
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .saydoGround()
        .task {
            guard prepared == nil else { return }
            let granted = await AppRouter.microphonePermission()
            prepared = Prepared(viewModel: router.makePromiseViewModel(), microphoneGranted: granted)
        }
    }
}

/// 答える画面。頭脳は 1 回だけ作る。
private struct FollowUpCover: View {

    let router: AppRouter
    let commitment: CommitmentSnapshot

    @State private var viewModel: FollowUpViewModel?

    var body: some View {
        Group {
            if let viewModel {
                FollowUpView(viewModel: viewModel)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .saydoGround()
        .task {
            guard viewModel == nil else { return }
            viewModel = router.makeFollowUpViewModel(for: commitment)
        }
    }
}
