import SwiftUI
import SwiftData

/// 初回起動時、「自分」が未登録の場合に表示する。
/// つながりマップは自分を起点に成立するため、使い始める前に必ず1回だけ通す。
struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @FocusState private var nameFieldFocused: Bool

    var onComplete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(AppTheme.ai.opacity(0.08))
                        .frame(width: 88, height: 88)
                    Image(systemName: "person.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(AppTheme.ai)
                }

                Text("はじめに、あなたのお名前を")
                    .font(.minchoTitle(19, relativeTo: .title3))
                    .foregroundStyle(AppTheme.ink)

                Text("つながりマップは、あなたを起点に表示されます。ここで登録した名前が中心になります。")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.inkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            VStack(spacing: 14) {
                TextField("例: 山田 太郎", text: $name)
                    .accessibilityIdentifier("onboarding.nameField")
                    .textFieldStyle(.plain)
                    .font(.body)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(AppTheme.paperRaised)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(AppTheme.ruleStrong, lineWidth: 1)
                    )
                    .focused($nameFieldFocused)
                    .submitLabel(.done)
                    .onSubmit(start)

                Button(action: start) {
                    Text("はじめる")
                        .font(.body.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("onboarding.startButton")
                .tint(AppTheme.ai)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 32)
            .padding(.top, 36)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.paper)
        .onAppear {
            // 少し間を置いてからフォーカスすると、画面遷移中のキーボード表示のもたつきを避けられる
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                nameFieldFocused = true
            }
        }
    }

    private func start() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let person = Person(name: trimmed, isSelf: true)
        context.insert(person)
        try? context.save()
        onComplete()
    }
}

#Preview {
    OnboardingView(onComplete: {})
        .modelContainer(for: [Person.self, Gathering.self], inMemory: true)
}
