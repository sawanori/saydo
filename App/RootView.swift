import SwiftUI
import SaydoCore

/// アプリの外枠（実装計画 §8）。
///
/// `TabView` は「今日」「記録」の 2 タブだけ。設定は「今日」の右上（task_013）。
/// 通知タップは `TodayView` を経由せず `SessionView` を直接出して即開始する。
///
/// 統合時の差し替え:
/// - `TodayTabPlaceholder` → `TodayView`（task_010 / エージェント F）
/// - `TimelineTabPlaceholder` → `TimelineView`（task_012 / エージェント B。上部に `InsightCardView`）
/// - `OnboardingPlaceholder` → `OnboardingView`（task_013 / エージェント C）
struct RootView: View {

    let router: AppRouter

    var body: some View {
        Group {
            if router.hasCompletedOnboarding {
                tabs
            } else {
                OnboardingPlaceholder { router.completeOnboarding() }
            }
        }
        .fullScreenCover(isPresented: isSessionPresented) {
            SessionCover(router: router)
        }
    }

    private var tabs: some View {
        TabView {
            TodayTabPlaceholder {
                Task { await router.startManualSession() }
            }
            .tabItem { Text(RootCopy.todayTab) }

            TimelineTabPlaceholder()
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

// MARK: - タブの中身（統合時に差し替える）

/// 「今日」タブの仮置き。宣言カードと通知再許可の導線は `TodayView`（F）が持つ。
private struct TodayTabPlaceholder: View {

    let onSpeakNow: () -> Void

    var body: some View {
        VStack {
            Spacer()
            Button(action: onSpeakNow) {
                Text(RootCopy.speakNow)
                    .saydoText(.screenTitle)
                    .frame(maxWidth: .infinity)
                    .frame(height: SaydoTheme.Metric.primaryButtonHeight)
                    .background(
                        Capsule().fill(SaydoTheme.Palette.chipFill)
                    )
                    .overlay(
                        Capsule().stroke(SaydoTheme.Palette.hairline, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Layout.sideMargin)
            .padding(.bottom, Layout.bottomMargin)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .saydoGround()
    }

    private enum Layout {
        static let sideMargin: CGFloat = 30
        static let bottomMargin: CGFloat = 40
    }
}

/// 「記録」タブの仮置き。日ごとの一覧は `TimelineView`（B）が持つ。
private struct TimelineTabPlaceholder: View {
    var body: some View {
        Text(RootCopy.timelineEmpty)
            .saydoText(.list)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .saydoGround()
    }
}

/// オンボーディングの仮置き。権限・時刻・音声モデルの案内は `OnboardingView`（C）が持つ。
private struct OnboardingPlaceholder: View {

    let onStart: () -> Void

    var body: some View {
        VStack(spacing: Layout.spacing) {
            Spacer()
            Text(RootCopy.onboardingLead)
                .saydoWrappingQuestion()
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(action: onStart) {
                Text(RootCopy.onboardingStart)
                    .saydoText(.screenTitle)
                    .frame(maxWidth: .infinity)
                    .frame(height: SaydoTheme.Metric.primaryButtonHeight)
                    .background(
                        Capsule().fill(SaydoTheme.Palette.chipFill)
                    )
                    .overlay(
                        Capsule().stroke(SaydoTheme.Palette.hairline, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Layout.sideMargin)
        .padding(.bottom, Layout.bottomMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .saydoGround()
    }

    private enum Layout {
        static let spacing: CGFloat = 24
        static let sideMargin: CGFloat = 30
        static let bottomMargin: CGFloat = 40
    }
}
