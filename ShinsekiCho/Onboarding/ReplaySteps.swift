import SwiftUI

struct ReplaySelfStep: View {
    let snapshot: OnboardingFamilySnapshot
    let onNext: () -> Void

    var body: some View {
        OnboardingStepLayout(
            symbol: "person.crop.circle.badge.checkmark",
            title: "自分の登録",
            message: "あなたを起点に、親戚との関係を記録します。"
        ) {
            VStack(spacing: 16) {
                replayPhoto
                    .accessibilityHidden(true)
                ReplayStatusRow(role: "自分", name: snapshot.selfName)
                guidance
                nextButton(identifier: "onboarding.replay.self.next")
            }
        }
        .accessibilityIdentifier("onboarding.replay.self")
    }

    @ViewBuilder
    private var replayPhoto: some View {
        if let image = PersonPhotoSupport.image(from: snapshot.selfPhotoData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 88, height: 88)
                .clipShape(Circle())
                .overlay { Circle().stroke(AppTheme.ruleStrong, lineWidth: 1.5) }
        } else {
            ZStack {
                Circle().fill(AppTheme.paperRaised)
                Text(PersonPhotoSupport.initial(for: snapshot.selfName))
                    .font(.minchoTitle(30, relativeTo: .largeTitle))
                    .foregroundStyle(AppTheme.ai)
            }
            .frame(width: 88, height: 88)
            .overlay { Circle().stroke(AppTheme.ruleStrong, lineWidth: 1.5) }
        }
    }

    private var guidance: some View {
        Label("名前や写真は人物詳細の「編集」から変更できます", systemImage: "pencil")
            .font(.caption)
            .foregroundStyle(AppTheme.inkSoft)
    }

    private func nextButton(identifier: String) -> some View {
        Button("次へ", action: onNext)
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.ai)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier(identifier)
    }
}

struct ReplayFamilyStep: View {
    let snapshot: OnboardingFamilySnapshot
    let onNext: () -> Void

    var body: some View {
        OnboardingStepLayout(
            symbol: "person.3",
            title: "近い家族の登録",
            message: "登録済みの家族を確認できます。ここでは関係を変更しません。"
        ) {
            VStack(spacing: 12) {
                if snapshot.familyItems.isEmpty {
                    ReplayEmptyStatus(message: "近い家族はまだ登録されていません")
                } else {
                    ForEach(snapshot.familyItems) { item in
                        ReplayStatusRow(role: item.role, name: item.name)
                    }
                }
                editGuidance
                Button("次へ", action: onNext)
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.ai)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("onboarding.replay.family.next")
            }
        }
        .accessibilityIdentifier("onboarding.replay.family")
    }

    private var editGuidance: some View {
        Label(
            "追加・変更は人物詳細の「関係を編集する」から行えます",
            systemImage: "person.line.dotted.person.fill"
        )
        .font(.caption)
        .foregroundStyle(AppTheme.inkSoft)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }
}

struct ReplayGrandparentStep: View {
    let snapshot: OnboardingFamilySnapshot
    let onNext: () -> Void

    var body: some View {
        OnboardingStepLayout(
            symbol: "figure.2.and.child.holdinghands",
            title: "祖父母の登録",
            message: "祖父母も登録すると、世代をまたいだつながりを辿れます。"
        ) {
            VStack(spacing: 12) {
                if snapshot.grandparentItems.isEmpty {
                    ReplayEmptyStatus(message: "祖父母はまだ登録されていません")
                } else {
                    ForEach(snapshot.grandparentItems) { item in
                        ReplayStatusRow(role: item.role, name: item.name)
                    }
                }
                Label(
                    "追加・変更は人物詳細の「関係を編集する」から行えます",
                    systemImage: "pencil"
                )
                .font(.caption)
                .foregroundStyle(AppTheme.inkSoft)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)

                Button("次へ", action: onNext)
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.ai)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("onboarding.replay.grandparents.next")
            }
        }
        .accessibilityIdentifier("onboarding.replay.grandparents")
    }
}

private struct ReplayStatusRow: View {
    let role: String
    let name: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppTheme.ai)
            VStack(alignment: .leading, spacing: 2) {
                Text(role)
                    .font(.caption)
                    .foregroundStyle(AppTheme.inkSoft)
                Text(name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(AppTheme.ink)
            }
            Spacer()
            Text("登録済み")
                .font(.caption)
                .foregroundStyle(AppTheme.ai)
        }
        .padding(14)
        .background(AppTheme.paperRaised, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppTheme.rule, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("onboarding.replay.registered.\(role).\(name)")
    }
}

private struct ReplayEmptyStatus: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "info.circle")
            .font(.subheadline)
            .foregroundStyle(AppTheme.inkSoft)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(AppTheme.paperRaised, in: RoundedRectangle(cornerRadius: 12))
    }
}
