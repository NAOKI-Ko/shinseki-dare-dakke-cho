# Phase 10.6 Release Candidate Gate

更新日: 2026-08-13

## RC summary

- Branch: `release/rc-1.0`
- Baseline: `fd274b1eb0f67c57f1a4575270c38400ac436ec3`
- FamilyGraph RC alignment fix: `fd274b1eb0f67c57f1a4575270c38400ac436ec3`
- App: 親戚だれだっけ帳
- Bundle ID: `com.naoki-ko.shinsekicho`
- Version / Build: `1.0 (10)`
- Deployment target: iOS 17.0
- StoreKit Product ID: `com.naokiko.shinsekicho.fullaccess`
- StoreKit Configuration: `None`
- Phase 10.6 production code changes: none

Phase 10.6ではproduction実装を変更していない。最新のreview済みFamilyGraph alignment修正を含むbaselineを、そのままRelease build、Unit/UI regression、Archive、実機インストール／起動で検証した。

## Identity / privacy

- App icon: Release archive内にiPhone/iPad iconを確認
- Privacy Manifest: Release archive内の`PrivacyInfo.xcprivacy`を確認
- Encryption: `ITSAppUsesNonExemptEncryption = false`
- Privacy Policy: <https://naoki-ko.github.io/shinsekicho-privacy/> を2026-08-13にHTTP取得できた
- 公開ページの最終更新日は2026年8月13日
- 公開ページにbackup export、対象情報、利用者が保存先を選ぶこと、開発者が受信・保存・閲覧しないこと、独自serverへ自動送信しないことが記載されている
- Support URL: 未設定。`HUMAN GATE — Support URL required`

## Build / test results

### Release build

- Release clean build: PASS
- Destination: generic iOS Simulator
- Derived Data: `/tmp/ShinsekiChoPhase106RCBuild`
- 新規compiler error: 0
- 重大warning: 0
- AppIntents metadata extractionの依存なし通知のみ

### Unit tests

- Deterministic result: 312 passed / 0 failed / 0 skipped
- Result bundle: `/tmp/ShinsekiChoPhase106RCUnitDeterministic.xcresult`
- 全Unit実行では既知のStoreKit storefront/daemon依存integration 1件が、JPN設定を適用できず`$3.99`を返して停止した
- 上記1件だけを除外した再実行はPASS。production logic由来の新規FAILは0
- Keychainを含むその他Unit testはPASS

### UI regression

- Result: 40 passed / 0 failed / 0 skipped
- Result bundle: `/tmp/ShinsekiChoPhase106RCUIAll.xcresult`
- Device: iPhone 17 Pro Simulator / iOS 26.5
- Onboarding: first run / completion / skip / replay / expired replay PASS
- Person: list / add / v3 persistence / detail / Memory Summary / relation edit PASS
- FamilyGraph: initial / 0.4 / 0.6 / 1.0 / 2.5 / pan / reset / long press / expand / navigation PASS
- Merge / relationship correction: PASS
- Search: multi-token AND / spouse-side / Gathering / no result / trial regression PASS
- Gathering: empty / add導線 / delete confirmation / detail PASS
- Gathering Prep: previous / next / detail return / finish / expired trial PASS
- Backup: export導線 / restore preview / cancel PASS
- Accessibility: Accessibility XXXL / Dark Mode / node labels / Memory Summary / Prep progress PASS
- Performance: medium / 50-person / 100-person smoke PASS

## FamilyGraph RC regression

- Baselineのalignment fix SHA: `fd274b1eb0f67c57f1a4575270c38400ac436ec3`
- 0.4 / 0.6 / 1.0 / 2.5でnode中心とedge endpointの距離を既存0.5pt toleranceで検証: PASS
- 20人以上、50人、100人smoke: PASS
- pan / zoom / reset / expand / long press回帰: PASS
- Simulator UI regressionでnode/edge再ズレなし
- 実機60秒操作による最終目視はHuman Gate

## Physical device

- Device: iPhone 17 (`iPhone18,3`)
- Device name: iPhone16
- OS: iOS 26.5.1 (`23F81`)
- Developer Mode: enabled
- Build configuration: Release archive
- Archive app install: PASS
- Bundle launch: PASS
- 起動後の実機process存在: PASS

実機へのインストールと起動までは自動確認した。次は人手で画面と端末設定を操作する必要があるためHuman Gateとして残す。

- 主要画面のcold-launch smoke（Person List / Detail / FamilyGraph / Search / Gathering / Prep / Backup / PurchaseSheet）
- VoiceOverの読み上げ順、Rotor、custom action、focus移動
- Default / Accessibility XXXLの実機表示
- Dark Modeの実機contrast
- FamilyGraph 60秒操作、FPS/hitch、node/edge目視
- Instruments Memory / Leaks / Energy Log

## StoreKit

- Product IDのコード・local StoreKit file一致: PASS
- Local product type: Non-Consumable
- Local StoreKit price: JPN / 600
- 価格表示は`Product.displayPrice`を使用し、固定価格なし
- Product取得、購入、pending/cancel、current entitlements、restore APIのUnit regression: PASS
- Shared SchemeのStoreKit Configuration: `None`
- Release archiveに正しいproduct ID文字列を確認
- 旧product IDのproduction参照: 0

以前のversion 1.0 build 10では日本Sandbox storefrontで商品取得、¥600表示、購入完了まで確認済み。ただし、現RCを新規インストールした状態でのproduct fetch、cancel、purchase、restore、relaunch entitlement、offline動作はPhase 10.6のHuman Gateとして再確認が必要。

## Backup / privacy handling

- Simulator UI regression: export導線およびrestore preview/cancel PASS
- 保存先は利用者が選択し、個人情報warningとreplace-all確認がある実装を静的確認
- app独自server upload経路なし
- Physical Files picker export / restore / round-trip: HUMAN GATE
- Round-tripではPerson数、isSelf、spouse、parent-child、Gathering、attendee、photo有無の一致確認が必要

## Release binary audit

- `PerformanceFixture.swift`と全UI seed/runtime triggerは`#if DEBUG`内
- Release binaryに`-ui-testing*`、`PerformanceFixture`、debug fixture文字列なし
- Release archiveにtest bundleなし
- production loggerはStoreKit技術情報のみ
- Person name / phone / email / address / memo / backup JSON / relationship dataのログ出力なし
- 電話・メール等の文字列は機能UI/model識別子としてbinaryに含まれるが、値のloggingではない

## Privacy Manifest

- Archive path: `/tmp/ShinsekiChoPhase106RC.xcarchive/Products/Applications/ShinsekiCho.app/PrivacyInfo.xcprivacy`
- `NSPrivacyTracking = false`
- `NSPrivacyCollectedDataTypes = []`
- UserDefaults required reason: `CA92.1`

## Archive / distribution

- Archive: PASS
- Archive path: `/tmp/ShinsekiChoPhase106RC.xcarchive`
- Archive identity: `1.0 (10)`, `com.naoki-ko.shinsekicho`, arm64
- App icon / Privacy Manifest: included
- Signing: Apple Development / automatic team profile。このローカルArchiveのApp Store再署名・配布はOrganizer側で行う
- Shallow bundle validation during Archive: PASS
- Organizer `Validate App`: HUMAN GATE（App Store Connect認証が必要）
- TestFlight upload: 未実施
- TestFlight smoke: 未実施
- App Review本番提出: 未実施

## Screenshot readiness

- Memory Summary、FamilyGraph、Gathering Prep、Search、Backupは既存Simulator UI regressionで表示回帰PASS
- Store掲載候補には最新FamilyGraph alignment fixが入った画面だけを使用する
- 既存未追跡`Screenshots/iap_review_paywall.png`は指示どおり変更していない
- 新しいIAP review screenshotは生成していない。現RC PurchaseSheetの実機表示確認はHuman Gate

## App Store Connect readiness

2026-08-13の読み取り確認ではApp Store Connectがloginへ遷移し、認証済みsessionを利用できなかった。このため次をHuman Gateとして残す。

- App Privacy
- Primary / Secondary Category
- Age Rating
- IAP Product status / 日本価格 / 提供地域
- Privacy Policy URL
- Support URL
- Screenshots
- Version/build 10の衝突有無
- Review Notes
- Validate App
- TestFlight upload / processing / install smoke

## Release blocker classification

### BLOCKER

- 自動Build/Test/Archive/実機install・launchで検出されたproduction blocker: 0

### HUMAN GATE

- Support URL required
- App Store Connect metadata確認
- 実機主要画面smoke
- 実機VoiceOver / Dynamic Type / Dark Mode
- 実機FamilyGraph 60秒操作 / Memory / Leaks / Energy
- 現RCでのStoreKit Sandbox fetch / purchase / cancel / restore / relaunch / offline
- Backup Files export / restore / round-trip
- Organizer Validate App
- TestFlight upload / smoke

### POST-RELEASE

- 軽微なspacing / animation preference
- 厳密60fpsの追加計測（操作blockerがない場合）
- 正式`v1.0.0` tag
- App Review本番提出
- feature / release branch cleanup

## Merge / tag decision

重要Human Gateが残っているため、Phase 10.6の条件に従ってmainへmergeしない。`v1.0.0-rc1` tagも作成しない。正式`v1.0.0` tagとApp Review本番提出は行わない。
