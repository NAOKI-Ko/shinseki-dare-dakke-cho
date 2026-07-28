import SwiftData
import SwiftUI

/// 「自分」の登録処理を既存のOnboardingViewへ任せ、その直後に使い方を案内する。
struct OnboardingFlowView: View {
  private enum Step {
    case registration
    case guide
  }

  @State private var step: Step = .registration

  var onRegistrationComplete: () -> Void
  var onComplete: () -> Void

  init(
    startAtGuide: Bool = false,
    onRegistrationComplete: @escaping () -> Void,
    onComplete: @escaping () -> Void
  ) {
    _step = State(initialValue: startAtGuide ? .guide : .registration)
    self.onRegistrationComplete = onRegistrationComplete
    self.onComplete = onComplete
  }

  var body: some View {
    Group {
      switch step {
      case .registration:
        OnboardingView {
          onRegistrationComplete()
          withAnimation(.easeInOut(duration: 0.3)) {
            step = .guide
          }
        }
        .transition(.opacity)
      case .guide:
        OnboardingGuideView(onComplete: onComplete)
          .transition(.opacity)
      }
    }
  }
}

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

private struct OnboardingGuideView: View {
  @State private var page = 0

  var onComplete: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Spacer()
        Button("スキップ", action: onComplete)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(AppTheme.inkSoft)
          .accessibilityIdentifier("onboarding.guide.skipButton")
      }
      .padding(.horizontal, 24)
      .padding(.top, 16)

      TabView(selection: $page) {
        guideCard(
          title: "人物をタップして、\nつながりを広げる",
          message: "人物のアイコンをタップすると、その人の家族がつながりに加わります。",
          illustration: AnyView(GuideMapIllustration())
        )
        .accessibilityIdentifier("onboarding.guide.page1")
        .tag(0)

        guideCard(
          title: "長押しで、\nその場ですばやく登録",
          message: "人物のアイコンを長押しすると、その場で家族を追加できます。詳しい情報はあとから編集できます。",
          illustration: AnyView(GuideLongPressIllustration())
        )
        .accessibilityIdentifier("onboarding.guide.page2")
        .tag(1)
      }
      .tabViewStyle(.page(indexDisplayMode: .always))
      .indexViewStyle(.page(backgroundDisplayMode: .always))

      Button(action: advance) {
        Text(page == 0 ? "次へ" : "使いはじめる")
          .font(.body.weight(.bold))
          .frame(maxWidth: .infinity)
          .padding(.vertical, 4)
      }
      .buttonStyle(.borderedProminent)
      .tint(AppTheme.ai)
      .accessibilityIdentifier(
        page == 0
          ? "onboarding.guide.nextButton"
          : "onboarding.guide.completeButton"
      )
      .padding(.horizontal, 32)
      .padding(.bottom, 28)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(AppTheme.paper)
  }

  private func guideCard(
    title: String,
    message: String,
    illustration: AnyView
  ) -> some View {
    VStack(spacing: 26) {
      Spacer(minLength: 12)
      illustration
        .frame(height: 220)
        .padding(.horizontal, 30)

      Text(title)
        .font(.minchoTitle(22, relativeTo: .title2))
        .foregroundStyle(AppTheme.ink)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)

      Text(message)
        .font(.body)
        .foregroundStyle(AppTheme.inkSoft)
        .multilineTextAlignment(.center)
        .lineSpacing(5)
        .padding(.horizontal, 38)

      Spacer(minLength: 34)
    }
  }

  private func advance() {
    if page == 0 {
      withAnimation(.easeInOut(duration: 0.25)) {
        page = 1
      }
    } else {
      onComplete()
    }
  }
}

private struct GuideMapIllustration: View {
  private let beadSize: CGFloat = 56

  var body: some View {
    GeometryReader { proxy in
      let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
      let points = [
        CGPoint(x: proxy.size.width * 0.20, y: proxy.size.height * 0.28),
        CGPoint(x: proxy.size.width * 0.80, y: proxy.size.height * 0.28),
        CGPoint(x: proxy.size.width * 0.24, y: proxy.size.height * 0.78),
        CGPoint(x: proxy.size.width * 0.76, y: proxy.size.height * 0.78),
      ]

      ZStack {
        Canvas { context, _ in
          for point in points {
            var path = Path()
            path.move(to: center)
            let middleY = (center.y + point.y) / 2
            path.addCurve(
              to: point,
              control1: CGPoint(x: center.x, y: middleY),
              control2: CGPoint(x: point.x, y: middleY)
            )
            context.stroke(
              path,
              with: .color(AppTheme.ruleStrong),
              lineWidth: 1.5
            )
          }
        }

        guideBead("自", color: AppTheme.attention, emphasized: true)
          .position(center)

        ForEach(Array(points.enumerated()), id: \.offset) { index, point in
          guideBead(["父", "母", "子", "配"][index], color: AppTheme.ai)
            .position(point)
        }
      }
    }
    .padding(8)
    .background(AppTheme.paperRaised)
    .clipShape(RoundedRectangle(cornerRadius: 20))
    .overlay {
      RoundedRectangle(cornerRadius: 20)
        .stroke(AppTheme.rule, lineWidth: 1)
    }
  }

  private func guideBead(
    _ initial: String,
    color: Color,
    emphasized: Bool = false
  ) -> some View {
    ZStack {
      if emphasized {
        Circle()
          .stroke(AppTheme.attention.opacity(0.22), lineWidth: 1)
          .frame(width: beadSize + 18, height: beadSize + 18)
      }
      Circle()
        .fill(color.opacity(0.10))
        .frame(width: beadSize, height: beadSize)
        .overlay {
          Circle().stroke(color, lineWidth: 1.5)
        }
      Text(initial)
        .font(.minchoTitle(17, relativeTo: .headline))
        .foregroundStyle(color)
    }
  }
}

private struct GuideLongPressIllustration: View {
  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 20)
        .fill(AppTheme.paperRaised)

      Circle()
        .stroke(AppTheme.ai.opacity(0.14), lineWidth: 1)
        .frame(width: 124, height: 124)
      Circle()
        .stroke(AppTheme.ai.opacity(0.24), lineWidth: 1)
        .frame(width: 94, height: 94)
      Circle()
        .fill(AppTheme.ai.opacity(0.10))
        .frame(width: 66, height: 66)
        .overlay {
          Circle().stroke(AppTheme.ai, lineWidth: 1.5)
        }
        .overlay {
          Text("親")
            .font(.minchoTitle(18, relativeTo: .headline))
            .foregroundStyle(AppTheme.ai)
        }

      Image(systemName: "hand.tap.fill")
        .font(.system(size: 34, weight: .regular))
        .foregroundStyle(AppTheme.attention)
        .offset(x: 48, y: 54)

      Label("家族を追加", systemImage: "plus.circle.fill")
        .font(.caption.weight(.semibold))
        .foregroundStyle(AppTheme.ai)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(AppTheme.ai.opacity(0.10), in: Capsule())
        .offset(y: -78)
    }
    .overlay {
      RoundedRectangle(cornerRadius: 20)
        .stroke(AppTheme.rule, lineWidth: 1)
    }
  }
}

#Preview {
  OnboardingFlowView(onRegistrationComplete: {}, onComplete: {})
    .modelContainer(for: [Person.self, Gathering.self], inMemory: true)
}
