import PhotosUI
import SwiftUI
import UIKit

struct SelfStep: View {
    @Binding var draft: OnboardingDraft
    let onNext: () -> Void

    @State private var selectedPhoto: PhotosPickerItem?

    var body: some View {
        OnboardingStepLayout(
            symbol: "person.crop.circle.badge.checkmark",
            title: "まず、自分を登録",
            message: "名前だけで始められます。写真はあとからでも追加できます。"
        ) {
            VStack(spacing: 16) {
                photoPreview
                    .accessibilityHidden(true)

                TextField("名前", text: $draft.selfName)
                    .textContentType(.name)
                    .submitLabel(.done)
                    .padding(14)
                    .background(AppTheme.paperRaised, in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(AppTheme.ruleStrong, lineWidth: 1)
                    }
                    .accessibilityIdentifier("onboarding.self.name")
                    .accessibilityLabel("自分の名前")

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label(
                        draft.selfPhotoData == nil ? "写真を選ぶ（任意）" : "写真を変更",
                        systemImage: "photo"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(AppTheme.ai)
                .accessibilityIdentifier("onboarding.self.photo")
                .onChange(of: selectedPhoto) { _, item in
                    guard let item else { return }
                    Task {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            await MainActor.run { draft.selfPhotoData = data }
                        }
                    }
                }

                Button("次へ", action: onNext)
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.ai)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .disabled(!draft.isSelfValid)
                    .accessibilityIdentifier("onboarding.self.next")
            }
        }
        .accessibilityIdentifier("onboarding.self")
    }

    @ViewBuilder
    private var photoPreview: some View {
        if let image = PersonPhotoSupport.image(from: draft.selfPhotoData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 88, height: 88)
                .clipShape(Circle())
                .overlay { Circle().stroke(AppTheme.ruleStrong, lineWidth: 1.5) }
        } else {
            ZStack {
                Circle().fill(AppTheme.paperRaised)
                Text(PersonPhotoSupport.initial(for: draft.selfName))
                    .font(.minchoTitle(30, relativeTo: .largeTitle))
                    .foregroundStyle(AppTheme.ai)
            }
            .frame(width: 88, height: 88)
            .overlay { Circle().stroke(AppTheme.ruleStrong, lineWidth: 1.5) }
        }
    }
}
