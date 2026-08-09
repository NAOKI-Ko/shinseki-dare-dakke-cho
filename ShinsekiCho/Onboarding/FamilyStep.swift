import SwiftUI

struct FamilyStep: View {
    @Binding var draft: OnboardingDraft
    let onNext: () -> Void

    var body: some View {
        OnboardingStepLayout(
            symbol: "person.3",
            title: "近い家族を追加",
            message: "分かる人だけで大丈夫です。詳しい情報や関係はあとから編集できます。"
        ) {
            VStack(spacing: 12) {
                RelativeDraftRow(title: "父", draft: $draft.father, identifier: "father")
                RelativeDraftRow(title: "母", draft: $draft.mother, identifier: "mother")
                RelativeDraftRow(title: "配偶者", draft: $draft.spouse, identifier: "spouse")
                RelativeDraftRow(title: "兄弟・姉妹", draft: $draft.sibling, identifier: "sibling")

                if draft.sibling.isSelected,
                   !draft.father.isSelected,
                   !draft.mother.isSelected {
                    Text("親も登録すると、兄弟・姉妹とのつながりが自動で結ばれます。")
                        .font(.caption)
                        .foregroundStyle(AppTheme.inkSoft)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button("次へ", action: onNext)
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.ai)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .disabled(!draft.isFamilyValid)
                    .accessibilityIdentifier("onboarding.family.next")
                    .padding(.top, 8)
            }
        }
        .accessibilityIdentifier("onboarding.family")
    }
}

struct RelativeDraftRow: View {
    let title: String
    @Binding var draft: OnboardingRelativeDraft
    let identifier: String
    var isEnabled = true

    var body: some View {
        VStack(spacing: 10) {
            Button {
                guard isEnabled else { return }
                draft.isSelected.toggle()
                if !draft.isSelected { draft.name = "" }
            } label: {
                HStack {
                    Image(systemName: draft.isSelected ? "checkmark.square.fill" : "square")
                        .foregroundStyle(draft.isSelected ? AppTheme.ai : AppTheme.ruleStrong)
                    Text(title)
                        .foregroundStyle(isEnabled ? AppTheme.ink : AppTheme.inkSoft)
                    Spacer()
                    Text(draft.isSelected ? "入力中" : "追加しない")
                        .font(.caption)
                        .foregroundStyle(AppTheme.inkSoft)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .accessibilityIdentifier("onboarding.relative.\(identifier).toggle")

            if draft.isSelected {
                TextField("\(title)の名前", text: $draft.name)
                    .textContentType(.name)
                    .padding(12)
                    .background(AppTheme.paper, in: RoundedRectangle(cornerRadius: 9))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(AppTheme.rule, lineWidth: 1)
                    }
                    .accessibilityIdentifier("onboarding.relative.\(identifier).name")
            }
        }
        .padding(14)
        .background(AppTheme.paperRaised, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppTheme.rule, lineWidth: 1)
        }
        .opacity(isEnabled ? 1 : 0.58)
    }
}
