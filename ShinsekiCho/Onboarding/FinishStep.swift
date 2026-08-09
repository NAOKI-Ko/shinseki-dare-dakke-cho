import SwiftUI

struct FinishStep: View {
    let onComplete: () -> Void

    var body: some View {
        OnboardingStepLayout(
            symbol: "calendar.badge.clock",
            title: "準備ができました",
            message: "法事や結婚式の前に、会う人の顔や関係を思い出せます。"
        ) {
            VStack(spacing: 18) {
                Label("登録内容はいつでも追加・修正できます", systemImage: "pencil")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.inkSoft)

                Button("親戚帳を開く", action: onComplete)
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.ai)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("onboarding.finish.complete")
            }
        }
        .accessibilityIdentifier("onboarding.finish")
    }
}
