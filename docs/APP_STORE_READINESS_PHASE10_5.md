# Phase 10.5 — App Store Readiness

実施日: 2026-08-12

Baseline: `0253f8120597f62884b45728a4b3c642a9c96fd2`

## Readiness summary

| 領域 | 判定 | 内容 |
|---|---|---|
| アプリ本体 | READY | 正式名称、アイコン、Bundle ID、version/build、iOS 17対応を確認 |
| 権限・通信 | READY | `PhotosPicker`のみ。独自サーバー、広告、解析、追跡なし |
| StoreKit | READY | 非消費型1商品、動的価格、購入・復元・失敗状態を確認 |
| Privacy Manifest | READY | `UserDefaults`のRequired Reason `CA92.1`を追加 |
| Privacy Policy | BLOCKER | URLは公開済みだが、バックアップ書き出しの説明を追加して再公開する必要あり |
| App Store Connect metadata | HUMAN GATE | App Privacy、カテゴリ、年齢区分、IAP状態、価格、URLを人が確定 |
| Product screenshots | HUMAN GATE | 下記ストーリーに沿ってRelease候補データで撮影・upload |
| Archive / upload | HUMAN GATE | Phase 10.5では未実施 |

## App identity

| 項目 | 現在値 | 判定 |
|---|---|---|
| Display Name | 親戚だれだっけ帳 | READY |
| Product Name | `ShinsekiCho` | READY（bundle内部名） |
| Bundle Identifier | `com.naoki-ko.shinsekicho` | READY |
| Version | `1.0` | READY |
| Build | `10` | READY |
| Deployment Target | iOS 17.0 | READY。SwiftData・Observation等の採用方針と一致 |
| App Icon | iPhone/iPad/1024px、alphaなし | READY |
| Language | Japanese / Base | READY。日本語のみで提出可能 |

`MARKETING_VERSION`はproject上`1`だが、提出bundleの
`CFBundleShortVersionString`は`1.0`である。Phase 10.5ではversionを変更しない。
既存公開版との衝突有無はApp Store Connectで最終確認する。

## Permissions and local data

- 写真は`PhotosPicker`からユーザーが選んだ画像だけを読み込む。カメラ撮影、連絡先、
  位置情報、HealthKitは使用しない。
- `PhotosPicker`方式のためPhoto Library usage descriptionは不要。Info.plistに不要な
  permission descriptionはない。
- 人物・関係・集まり・写真はSwiftDataへ端末内保存する。
- 初回起動日はSecurity.frameworkのKeychainへ保存する。
- バックアップはユーザー操作でJSONを書き出し、ユーザーが選んだ保存先へコピーする。
  開発者サーバーへの送信はない。試用期限後もexportは利用できる。
- 電話・メールは`tel:` / `mailto:`で端末標準アプリを開くだけで、通信内容を取得しない。

## Network and dependencies

独自HTTP通信、API、ログイン、Cloud同期はない。ネットワーク利用はStoreKitによるAppleの
商品取得・購入・復元・entitlement確認だけ。オフラインでも保存済み人物の閲覧、検索、
つながり、集まり前予習、バックアップexportは利用できる。商品取得だけが失敗し、再読込UIを
表示する。

外部Package / SDKは0件。使用する主なApple frameworkはSwiftUI、SwiftData、PhotosUI、
StoreKit、Security、UIKit、UniformTypeIdentifiers、OSLog、Observation、Foundation。
広告SDK、analytics、crash reporting、ATT、IDFA、tracking domainはない。

## App Privacy draft

Appleの定義では「収集」は、開発者または第三者パートナーが後でアクセスできる形で端末外へ
送信することを指す。本アプリの入力情報と写真は端末内に留まり、ユーザー主導のbackup先にも
開発者はアクセスしないため、App Store Connectでは「データを収集しない」が実装と一致する。

| データカテゴリ | 回答案 | 根拠 |
|---|---|---|
| Contact Info | 収集しない | 氏名・電話・メール・住所は端末内のみ |
| Health & Fitness | 収集しない | Health APIなし。食事配慮の自由入力も外部送信なし |
| Financial Info | 収集しない | 決済情報はAppleが処理し、開発者は取得しない |
| Location | 収集しない | Location APIなし。居住地の手入力は端末内のみ |
| Sensitive Info | 収集しない | 続柄等は端末内のみ |
| Contacts | 収集しない | Contacts frameworkへのアクセスなし |
| User Content | 収集しない | 写真・メモ・backup内容を開発者へ送信しない |
| Identifiers | 収集しない | IDFA、独自account、端末identifierなし |
| Usage Data | 収集しない | analyticsなし |
| Diagnostics | 収集しない | crash/diagnostic SDKなし |
| Other Data | 収集しない | 独自telemetryなし |

Trackingは「なし」。ATT promptは不要であり追加しない。

## Privacy Policy

公開URL: `https://naoki-ko.github.io/shinsekicho-privacy/`

GitHub Pagesはpublic / HTTPS enforced / builtを確認した。ただし現在本文には
「すべて端末内にのみ保存」とあり、追加済みのユーザー主導backup exportが明記されていない。
提出前に少なくとも次の内容へ更新する。

> 記録は通常、利用者の端末内に保存されます。利用者がバックアップ書き出しを実行した場合に
> 限り、人物・関係・集まり・写真等を含むJSONファイルが、利用者自身が選択した保存先へ
> コピーされます。保存先にはiCloud Drive等の外部サービスが含まれる場合がありますが、
> 本アプリの開発者がバックアップ内容を受信・収集することはありません。

写真、StoreKit、第三者SDKなしの説明は現実装と一致する。Supportページを参照する文言は、
実際のSupport URL確定後にリンク可能な問い合わせ先へ更新する。

## Privacy Manifest / Required Reason API

`PrivacyInfo.xcprivacy`をapp targetへ追加した。

- `NSPrivacyTracking = false`
- `NSPrivacyCollectedDataTypes = []`
- `NSPrivacyTrackingDomains = []`
- `NSPrivacyAccessedAPICategoryUserDefaults`: `CA92.1`

`CA92.1`はオンボーディング進捗と旧Trial値のmigration用に、当該アプリだけがアクセスできる
UserDefaultsを読み書きする理由。File timestamp、disk space、system boot time、active keyboardsの
Required Reason APIを直接使用するコードは見つからなかった。

## StoreKit audit

- Product ID: `com.naokiko.shinsekicho.fullaccess`（コードと`.storekit`で一致）
- Type: Non-Consumable
- Trial: 初回起動から7日間。Apple subscription trialではない
- Price: `Product.displayPrice`のみ。商品未取得時に架空価格を表示しない
- Purchase: success / pending / cancelled / verification failure / unavailable / offlineを表示
- Restore: PurchaseSheetの「購入を復元」から`AppStore.sync()`を実行
- Entitlement: 起動・foreground復帰・Transaction updatesで検証
- Shared Scheme: StoreKit Configuration `None`
- Local `.storekit`: 明示的に選択したローカルテスト時だけ使用
- Subscription用語（月額、年額、自動更新、解約）はユーザー向け購入説明にない

既存IAP review screenshot `Screenshots/iap_review_paywall.png`は1284×2778、PNG、alphaなし。
購入内容、買い切りで解放される機能、復元ボタンが読める。ただし未追跡fileは変更していない。
提出時にはcurrent Productの`displayPrice`を読み込んだ同じbuildで再撮影し、価格表示を再確認する。

## Metadata draft

### App description

法事や結婚式、久しぶりの帰省で「あの人、誰だっけ？」と思ったことはありませんか。

「親戚だれだっけ帳」は、親戚の顔・名前・続柄や会話のきっかけを、手元でそっと確認するための
記録アプリです。

- 写真、連絡先、居住地、誕生日、好み、食事の配慮などを人物ごとに記録
- 珠と糸の「つながり」で、親子・配偶者などの関係をたどる
- 「この人を思い出す」で、最後に会った場所や会話メモをすばやく確認
- 法事や結婚式など、集まりの出席者をまとめて予習
- 名前を忘れても、地域・関係・集まり・好みなどの手掛かりから検索
- JSONバックアップで、大切な記録を自分で保存・復元

記録は通常すべて端末内に保存され、開発者のサーバーへ送信されません。バックアップを
書き出した場合だけ、ユーザーが選んだ保存先へコピーされます。広告・アクセス解析・ログインは
ありません。

初回起動から7日間は追加・編集機能を無料で試せます。期間終了後も登録済み記録の閲覧と
バックアップ書き出しは利用できます。フルアクセスは自動更新のない買い切りです。

### Subtitle candidates（各30文字以内）

1. 法事や結婚式の前に親戚を思い出す
2. 親戚の顔・名前・つながりをひと目で
3. 大切な親族の記憶を手元に残す

### Promotional text

親戚の顔やつながり、会話のきっかけを記録。法事や結婚式の前に、会う人をまとめて予習できます。

### Keywords candidate

`親戚,親族,家系図,法事,結婚式,家族,続柄,冠婚葬祭,人物記録,予習`

App Store Connectへ貼付する直前に日本語ローカライゼーションの100-byte/character表示で再確認する。

### Category candidates

- Primary: Lifestyle
- Secondary: Reference

最終選択はHuman Gate。App Store ConnectのPrimary Categoryと、必要に応じてXcode側categoryを
同じ値にする。

### Age rating answers

次はすべて「なし」の回答案: parental controls、age assurance、unrestricted web access、
広く配信されるuser-generated content、social media、messaging/chat、advertising、暴力、武器、
性的表現、薬物、恐怖、医療助言、gambling、simulated gambling、contest、loot box。
ローカルの自由入力は他ユーザーへ配信されないため、Apple定義のUser-Generated Contentには
該当しない。App Store Connectが算出するratingを保存前にHumanが確認する。

Copyright案: `© 2026 Naoki Kondo`

## Screenshot plan

架空人物のみを使い、各画像はkeyboard、不要alert、DEBUG文字なし、アニメーション完了後に撮影。

| 順 | 上部コピー | 画面・状態 |
|---:|---|---|
| 1 | 「あの人誰だっけ？」をすぐ確認 | 人物詳細「この人を思い出す」 |
| 2 | 親戚のつながりがひと目でわかる | 複数世代を展開したつながり |
| 3 | 法事や結婚式の前にまとめて予習 | 20人未満の見やすいGathering Prep |
| 4 | 名前を忘れても手掛かりで検索 | 地域＋名前等の複合検索と理由表示 |
| 5 | 大切な記録を自分でバックアップ | 設定のbackup sectionと復元preview |
| 6（任意） | 記録は端末の中に | 設定の保存場所・privacy説明 |

IAP review screenshotはストア商品ページ用5〜6枚とは別の審査専用素材として扱う。

### Apple screenshot requirements（2026-08-12確認）

- 1〜10枚、JPEG/JPG/PNG、alpha/transparency不可。
- iPhone 6.9-inch portrait accepted sizes: 1260×2736、1290×2796、1320×2868。
- 6.9-inchを出せば同一UIの小型画面へ自動scale可能。
- 6.9-inchを出さない場合、6.5-inchは1284×2778または1242×2688が必要。
- iPad対応appなので13-inch portrait 2064×2752または2048×2732も必要。

## App Review Notes draft

本アプリはログイン不要で、デモアカウントも不要です。

初回起動後、オンボーディングで自分の名前を登録するかスキップして主要画面へ進めます。人物の
追加は「親戚」タブ右上の＋、関係編集は人物詳細の「関係を編集する」、集まり追加は「集まり」
タブ右上の＋から確認できます。

初回起動から7日間、人物・関係・集まりの追加と編集を無料で試せます。これはAppleの
subscription trialではなく、端末内Keychainで管理するアプリ独自の試用期間です。自動更新は
ありません。試用中でも「設定」→「フルアクセスを購入」からPurchaseSheetへ到達できます。
PurchaseSheetには非消費型の買い切り商品と「購入を復元」が表示されます。Product IDは
`com.naokiko.shinsekicho.fullaccess`です。

試用期間終了後も登録済みデータの閲覧とbackup exportは利用できます。BackupはローカルJSON
fileで、ユーザーが選んだ保存先だけへ書き出します。独自server、account、analyticsはありません。

## Review path

1. Launchし、オンボーディングで名前を登録またはスキップ。
2. 「親戚」タブ右上＋で人物を追加。
3. 人物詳細で記憶サマリー・つながり・関係編集を確認。
4. 「集まり」タブで集まりを追加し、予習を開始。
5. 「設定」→「フルアクセスを購入」でPurchaseSheetを開く。
6. 同じsheet内の「購入を復元」を確認。

Demo account: not required。

## Verification evidence

- Release clean build: PASS
- Release bundle: Display Name、Bundle ID、version 1.0、build 10、iOS 17.0を確認
- Release bundle: `PrivacyInfo.xcprivacy`同梱と`CA92.1`を確認
- Release binary: UI/performance fixtureのlaunch argumentと架空人物文字列が存在しないことを確認
- TrialManager Unit Tests: 14 / 14 PASS
  - 既知のStoreKit daemon依存test 1件は従来どおり対象外
- PurchaseSheet / Backup smoke UI: 3 / 3 PASS
- Settings / onboarding replay / dark mode smoke UI: 3 / 3 PASS
- Current PurchaseSheet evidence:
  `/tmp/ShinsekiChoPhase105Evidence/0E92C5E6-2728-4CAF-BC85-C7E1F7D32DF4.png`

Current evidenceは商品未取得・再読込状態の回帰証拠で、価格入りIAP審査画像の代用ではない。
価格入り素材は実機SandboxまたはTestFlightでcurrent Productを取得して別途撮影する。

## Encryption / export compliance

独自暗号アルゴリズム、VPN、独自HTTPS/API通信はない。Apple標準のKeychainとStoreKitだけを
使用し、Info.plistは`ITSAppUsesNonExemptEncryption = NO`。App Store Connectでは
「非免除暗号化を実装していない」に相当する回答候補とし、最終回答はHuman Gate。

## Logging and crash audit

- production logはStoreKitの商品ID、localized price、エラー説明のみ。人物名、電話、メール、
  住所、メモ、写真、backup内容は出力しない。
- `fatalError`はSwiftData containerを生成できない起動不能時の1箇所だけ。
- Releaseで到達する通常操作経路に`try!`や強制castはない。
- UI/performance fixture分岐とseed本体を`#if DEBUG`へ閉じ、Releaseでは有効化されない。
- accessibility identifierは画面上の文字として表示されない。

## Human Gates

1. 公開Privacy Policyへbackup説明と実Support URLを反映。
2. Support URLを決定し、実際にアクセス可能か確認。
3. App Store ConnectのApp Privacyを「データを収集しない」で入力・確認。
4. IAP `com.naokiko.shinsekicho.fullaccess`のstatus、Non-Consumable、¥600、日本での提供を確認。
5. Sandbox/TestFlight実機で商品取得、購入、cancel、pending、restore、offlineを確認。
6. Categoryとage rating questionnaireを確定。
7. iPhone 6.9-inchとiPad 13-inchのproduct screenshotsを撮影・upload。
8. current buildのlocalized priceでIAP review screenshotを再撮影・upload。
9. App description、subtitle、promotional text、keywords、copyrightをApp Store Connectへ入力。
10. physical device smoke、Archive、Validate、upload、提出build選択を実施。

## Blockers

1. 公開Privacy Policyがユーザー主導backup exportを説明していない。公開文面更新まで提出しない。

コード上で見つかったPrivacy Manifest不足、Release fixture分離、iPad icon slotは本branchで修正済み。

## Apple official references

- Screenshot specifications: <https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/>
- Upload screenshots: <https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots/>
- App privacy details: <https://developer.apple.com/app-store/app-privacy-details/>
- Manage app privacy: <https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/>
- Privacy manifests: <https://developer.apple.com/documentation/bundleresources/privacy-manifest-files>
- Required Reason APIs: <https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api>
- Age ratings: <https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/>
- Submit an IAP: <https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase/>
- IAP information: <https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-information>
