import SwiftUI

struct GrandparentStep: View {
    @Binding var draft: OnboardingDraft
    let onSave: () -> Void
    let onSkip: () -> Void

    var body: some View {
        OnboardingStepLayout(
            symbol: "figure.2.and.child.holdinghands",
            title: "祖父母も追加しますか？",
            message: "ここは任意です。親を登録した側だけ追加できます。"
        ) {
            VStack(spacing: 12) {
                RelativeDraftRow(
                    title: "父方祖父",
                    draft: $draft.paternalGrandfather,
                    identifier: "paternalGrandfather",
                    isEnabled: draft.father.isSelected
                )
                RelativeDraftRow(
                    title: "父方祖母",
                    draft: $draft.paternalGrandmother,
                    identifier: "paternalGrandmother",
                    isEnabled: draft.father.isSelected
                )
                RelativeDraftRow(
                    title: "母方祖父",
                    draft: $draft.maternalGrandfather,
                    identifier: "maternalGrandfather",
                    isEnabled: draft.mother.isSelected
                )
                RelativeDraftRow(
                    title: "母方祖母",
                    draft: $draft.maternalGrandmother,
                    identifier: "maternalGrandmother",
                    isEnabled: draft.mother.isSelected
                )

                Button("登録して次へ", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.ai)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .disabled(!draft.areGrandparentsValid)
                    .accessibilityIdentifier("onboarding.grandparents.save")

                Button("祖父母はあとで", action: onSkip)
                    .foregroundStyle(AppTheme.inkSoft)
                    .accessibilityIdentifier("onboarding.grandparents.later")
            }
        }
        .accessibilityIdentifier("onboarding.grandparents")
    }
}
