import SwiftUI
import SaydoCore

/// アプリの外枠（実装計画 §8）。
///
/// `TabView` は「今日」「記録」の 2 タブだけ。設定は「今日」の右上（task_013）。
/// 通知タップは `TodayView` を経由せず `SessionView` を直接出して即開始する。
///
/// 「今日」は `TodayView`（task_010）、「記録」は `VoiceTimelineView`（task_012）で上部に
/// `InsightCardView`（task_016）。初回だけ `OnboardingView`（task_013）を出す。
struct RootView: View {

    let router: AppRouter

    @State private var notificationHealth: NotificationHealth?
    @State private var insightModel: InsightViewModel?
    @State private var isSettingsPresented = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if router.hasCompletedOnboarding {
                tabs
            } else {
                OnboardingView { router.completeOnboarding() }
            }
        }
        .fullScreenCover(isPresented: isSessionPresented) {
            SessionCover(router: router)
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView { router.reloadOnboardingState() }
        }
        .task(id: router.hasCompletedOnboarding) {
            guard router.hasCompletedOnboarding else { return }
            await router.rescheduleOnLaunch()
            notificationHealth = await NotificationScheduler.shared.health()
            if insightModel == nil {
                insightModel = InsightViewModel(repository: router.repository)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, router.hasCompletedOnboarding else { return }
            Task {
                notificationHealth = await NotificationScheduler.shared.health()
                await insightModel?.load()
            }
        }
        .onChange(of: router.sessionGeneration) { _, _ in
            Task { await insightModel?.load() }
        }
    }

    private var tabs: some View {
        TabView {
            TodayView(
                repository: router.repository,
                player: router.sharedPlayer,
                notificationHealth: notificationHealth,
                onStartSession: { sessionType in
                    Task { await router.startManualSession(sessionType) }
                },
                onOpenSettings: { isSettingsPresented = true }
            )
            // 会話を閉じたら作り直して、今日の宣言を読み直す。
            .id(router.sessionGeneration)
            .tabItem { Text(RootCopy.todayTab) }

            VoiceTimelineView(player: router.sharedPlayer) {
                if let insightModel {
                    InsightCardView(model: insightModel)
                }
            }
            .tabItem { Text(RootCopy.timelineTab) }
        }
        .tint(SaydoTheme.Palette.accent)
    }

    private var isSessionPresented: Binding<Bool> {
        Binding(
            get: { router.activeSession != nil },
            set: { isPresented in
                if !isPresented { router.dismissSession() }
            }
        )
    }
}

// MARK: - 会話の被せ

/// `SessionView` を出し、出た瞬間に会話を始める（起動 1.5 秒以内に TTS）。
private struct SessionCover: View {

    let router: AppRouter

    var body: some View {
        Group {
            if let viewModel = router.sessionViewModel {
                SessionView(viewModel: viewModel) {
                    router.dismissSession()
                }
            } else {
                Text(RootCopy.preparing)
                    .saydoText(.status)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .saydoGround()
            }
        }
        .task(id: router.activeSession?.id) {
            await router.beginSession()
        }
    }
}
