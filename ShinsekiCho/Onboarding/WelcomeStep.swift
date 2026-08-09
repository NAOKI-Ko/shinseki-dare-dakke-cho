import SwiftUI

struct WelcomeStep: View {
    let onNext: () -> Void

    var body: some View {
        OnboardingStepLayout(
            symbol: "person.2.circle",
            title: "親戚だれだっけ帳へようこそ",
            message: "親戚を忘れないための記録帳です。"
        ) {
            VStack(spacing: 22) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 72, weight: .light))
                    .foregroundStyle(AppTheme.attention)
                    .accessibilityHidden(true)

                Button("はじめる", action: onNext)
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.ai)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("onboarding.welcome.next")
            }
        }
        .accessibilityIdentifier("onboarding.welcome")
    }
}
