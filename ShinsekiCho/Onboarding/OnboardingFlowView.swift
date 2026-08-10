import SwiftData
import SwiftUI

enum OnboardingStep: Int, CaseIterable {
    case welcome
    case selfRegistration
    case family
    case grandparents
    case finish
}

struct OnboardingFlowView: View {
    @Environment(TrialManager.self) private var trialManager
    @Environment(\.modelContext) private var context

    let mode: OnboardingMode
    let existingSelf: Person?
    let onComplete: () -> Void
    let onSkip: () -> Void
    let replaySnapshot: OnboardingFamilySnapshot

    @State private var step: OnboardingStep = .welcome
    @State private var draft: OnboardingDraft
    @State private var errorMessage: String?
    @State private var showingPurchaseSheet = false

    init(
        mode: OnboardingMode,
        existingSelf: Person?,
        onComplete: @escaping () -> Void,
        onSkip: @escaping () -> Void
    ) {
        self.mode = mode
        self.existingSelf = existingSelf
        self.onComplete = onComplete
        self.onSkip = onSkip
        replaySnapshot = OnboardingFamilySnapshot(existingSelf: existingSelf)
        _draft = State(initialValue: OnboardingDraft(existingSelf: existingSelf))
    }

    var body: some View {
        VStack(spacing: 0) {
            if step != .finish {
                HStack {
                    if step != .welcome {
                        Button {
                            moveBack()
                        } label: {
                            Label("戻る", systemImage: "chevron.left")
                        }
                        .accessibilityIdentifier("onboarding.back")
                    }
                    Spacer()
                    Text("\(step.rawValue + 1) / 5")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppTheme.inkSoft)
                    Button("スキップ", action: onSkip)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.inkSoft)
                        .accessibilityIdentifier("onboarding.skip")
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }

            Group {
                switch step {
                case .welcome:
                    WelcomeStep(onNext: { move(to: .selfRegistration) })
                case .selfRegistration:
                    if mode == .replay {
                        ReplaySelfStep(
                            snapshot: replaySnapshot,
                            onNext: { move(to: .family) }
                        )
                    } else {
                        SelfStep(draft: $draft, onNext: { move(to: .family) })
                    }
                case .family:
                    if mode == .replay {
                        ReplayFamilyStep(
                            snapshot: replaySnapshot,
                            onNext: { move(to: .grandparents) }
                        )
                    } else {
                        FamilyStep(draft: $draft, onNext: { move(to: .grandparents) })
                    }
                case .grandparents:
                    if mode == .replay {
                        ReplayGrandparentStep(
                            snapshot: replaySnapshot,
                            onNext: completeReplayAndFinish
                        )
                    } else {
                        GrandparentStep(
                            draft: $draft,
                            onSave: saveAndFinish,
                            onSkip: clearGrandparentsAndFinish
                        )
                    }
                case .finish:
                    FinishStep(onComplete: onComplete)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppTheme.paper.ignoresSafeArea())
        .alert("登録できませんでした", isPresented: errorIsPresented) {
            Button("閉じる", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "入力内容を確認してください。")
        }
        .sheet(isPresented: $showingPurchaseSheet) {
            PurchaseSheet()
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func move(to destination: OnboardingStep) {
        withAnimation(.easeInOut(duration: 0.22)) {
            step = destination
        }
    }

    private func moveBack() {
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        move(to: previous)
    }

    private func clearGrandparentsAndFinish() {
        draft.paternalGrandfather = OnboardingRelativeDraft()
        draft.paternalGrandmother = OnboardingRelativeDraft()
        draft.maternalGrandfather = OnboardingRelativeDraft()
        draft.maternalGrandmother = OnboardingRelativeDraft()
        saveAndFinish()
    }

    private func saveAndFinish() {
        guard mode.allowsRegistration else {
            completeReplayAndFinish()
            return
        }
        guard trialManager.canEdit else {
            showingPurchaseSheet = true
            return
        }
        do {
            try OnboardingCompletionService.complete(
                mode: mode,
                draft: draft,
                existingSelf: existingSelf,
                in: context
            )
            move(to: .finish)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func completeReplayAndFinish() {
        do {
            try OnboardingCompletionService.complete(
                mode: .replay,
                draft: draft,
                existingSelf: existingSelf,
                in: context
            )
            move(to: .finish)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct OnboardingStepLayout<Content: View>: View {
    let symbol: String
    let title: String
    let message: String
    @ViewBuilder let content: Content

    init(
        symbol: String,
        title: String,
        message: String,
        @ViewBuilder content: () -> Content
    ) {
        self.symbol = symbol
        self.title = title
        self.message = message
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(AppTheme.ai.opacity(0.08))
                        .frame(width: 76, height: 76)
                    Image(systemName: symbol)
                        .font(.system(size: 29, weight: .medium))
                        .foregroundStyle(AppTheme.ai)
                }
                .padding(.top, 24)

                Text(title)
                    .font(.minchoTitle(22, relativeTo: .title2))
                    .foregroundStyle(AppTheme.ink)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.inkSoft)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)

                content
                    .padding(.top, 8)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
    }
}
