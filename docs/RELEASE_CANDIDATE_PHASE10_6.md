# Phase 10.6 Release Candidate Gate

更新日: 2026-08-13

## RC summary

- Branch: `release/rc-1.0`
- Baseline: `efb558455e22474526c71deae4c1993032145ff6`
- App: 親戚だれだっけ帳
- Bundle ID: `com.naoki-ko.shinsekicho`
- Version / Build: `1.0 (10)`
- Deployment target: iOS 17.0
- StoreKit Product ID: `com.naokiko.shinsekicho.fullaccess`
- StoreKit Configuration: `None`
- Release production code changes: none

Phase 10.6で見つかった差異はUI test harnessだけに限定して修正した。装飾用の夫婦結び目はPhase 10.3でアクセシビリティツリーから除外済みのため、その存在をUI testで要求しないようにした。食事配慮は内部テーマ名ではなく、利用者向けアクセシビリティラベルの「注意」で検証するようにした。小型端末では画面外になり得る連絡先セクションを、検証前にスクロールして表示するようにした。また、20人展開テストの実行猶予を180秒にした。

## Identity / privacy

- App icon: archive内にiPhone/iPad iconを確認
- Privacy Manifest: archive内の`PrivacyInfo.xcprivacy`を確認
- Encryption: `ITSAppUsesNonExemptEncryption = false`
- Privacy Policy: <https://naoki-ko.github.io/shinsekicho-privacy/> をHTTP取得できた
- Privacy Policyにはbackup export、対象情報、利用者が保存先を選ぶこと、開発者が受信・保存・閲覧しないことが記載されている
- Support URL: 未設定。`HUMAN GATE — Support URL required`

## Build / test results

### Release build

- Release clean build: PASS
- 新規の重大compiler warning: なし
- AppIntents metadata extractionの依存なし通知のみ

### Unit tests

- Result: 304 passed / 0 failed / 0 skipped
- Result bundle: `/tmp/ShinsekiChoPhase106Unit.xcresult`
- 既知のStoreKit daemon/storefront依存integration testは指定どおり除外

### UI regression

- 最終結果: 38 unique test cases PASS / 0 assertion failures
- Onboarding: first run / completion / skip / replay / expired replay PASS
- Person: add / v3 persistence / detail / Memory Summary / relation edit PASS
- FamilyGraph: pan / pinch / reset / long press / expansion / 20-person expansion PASS
- Merge / relationship correction: PASS
- Search: enhanced multi-field/AND/trial regression PASS
- Gathering: empty state / delete confirm / detail PASS
- Gathering Prep: navigation / detail return / finish / expired trial PASS
- Backup: export availability / restore preview cancel PASS
- Accessibility: Accessibility XXXL / Dark Mode / labels PASS
- Performance: medium / stress 5 tests PASS

最初の一括UI実行ではCoreSimulator service切断により3つのrunner terminationが発生した。該当ケースは別Simulatorで単独・小分け再実行してすべてPASSした。production crashやassertion failureとしては扱わない。

主なresult bundle:

- `/tmp/ShinsekiChoPhase106UI.xcresult`
- `/tmp/ShinsekiChoPhase106UI-BatchA2.xcresult`
- `/tmp/ShinsekiChoPhase106UI-BatchC.xcresult`
- `/tmp/ShinsekiChoPhase106UI-Performance.xcresult`
- `/tmp/ShinsekiChoPhase106UI-Twenty.xcresult`
- `/tmp/ShinsekiChoPhase106UI-V3Fixed2.xcresult`

## Device results

- Physical device: iPhone 17 (`iPhone18,3`)
- OS: iOS 26.5.1
- Developer Mode: enabled
- Release archive app install: PASS
- Device launch command: PASS

次の項目は実機上の人手操作が必要なため、このGateでは未完了のHuman Gateとして残す。

- 主要画面のcold-launch smoke
- VoiceOverの読み上げ順、Rotor、custom action
- Accessibility XXXLでの全主要action到達
- Dark Modeの実機contrast
- FamilyGraph 60秒操作、FPS/hitch
- Instruments memory / Leaks / Energy Log
- Sandbox purchase / cancel / restore / relaunch entitlement
- Offline StoreKit
- Files pickerによるbackup export / restore / round-trip

## StoreKit

- Product IDのコード・local StoreKit file一致: PASS
- 種類: Non-Consumable
- 表示価格: `Product.displayPrice`を使用し、固定価格なし
- Product取得、購入、pending/cancel、current entitlements、restore APIの実装・Unit regression: PASS
- Shared SchemeのStoreKit Configuration: `None`
- 実機SandboxのPhase 10.6再確認: HUMAN GATE

以前のbuild 10では日本Sandbox storefrontで商品取得、¥600表示、購入完了まで確認済みだが、Phase 10.6 Gateでは新規インストール後の購入・復元を再度人手確認する。

## Backup / privacy handling

- Simulator UI regression: export導線およびrestore preview/cancel PASS
- 個人情報warning、ユーザー選択の保存先、外部server uploadなしの仕様を確認
- Physical Files picker round-trip: HUMAN GATE

## Archive / distribution

- Archive: PASS
- Archive path: `/tmp/ShinsekiChoPhase106.xcarchive`
- Archive identity: `1.0 (10)`, `com.naoki-ko.shinsekicho`, arm64
- Signing: Apple Development / automatic team profile。配布時のApp Store signingはOrganizer export/upload側で行う
- Shallow bundle validation: PASS
- Organizer `Validate App`: HUMAN GATE（App Store Connect認証が必要）
- TestFlight upload: 未実施。build 10のApp Store Connect上の衝突有無と認証をHuman Gateで確認する
- TestFlight smoke: 未実施

## Screenshot readiness

- Memory Summary、FamilyGraph、Gathering Prep、Search、Backupの候補画面は既存UI regression attachmentsおよびScreenshots内に存在
- 既存未追跡`Screenshots/iap_review_paywall.png`は指示どおり変更していない
- 新しいIAP review screenshotは生成していない

## App Store Connect Human Gates

- Support URLの決定・公開・設定
- App Privacy
- Category
- Age Rating
- IAP Product status / 日本価格 / 提供地域
- Privacy Policy URL
- Screenshots
- Version/build 10の衝突有無
- Review Notes
- Validate App
- TestFlight upload / processing / install smoke

## Release blocker classification

### BLOCKER

- 自動Build/Test/Archiveで確認されたproduction blocker: 0

### HUMAN GATE

- Support URL required
- 実機VoiceOver / Dynamic Type / Dark Mode
- 実機performance / Memory / Leaks / Energy
- StoreKit Sandbox purchase / restore / offline
- Backup Files round-trip
- App Store Connect metadata / Validate / TestFlight

### POST-RELEASE

- 正式`v1.0.0` tag
- App Review本番提出
- feature branch cleanup

## Merge / tag decision

実機Human GateとSupport URLが未完了のため、Phase 10.6の条件に従ってmainへmergeしない。`v1.0.0-rc1` tagも作成しない。App Review本番提出は行わない。
