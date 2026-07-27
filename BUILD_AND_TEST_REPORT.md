# 親戚だれだっけ帳 — 構築・テスト報告

実施日: 2026-07-24（つながりマップ改修: 2026-07-25 / v3・家系色アニメーション更新: 2026-07-27）  
環境: Xcode 26.6 (17F113) / iPhone 17 Pro Simulator / iOS 26.5 / arm64  
対象: iOS 17.0以上

## 1. Xcodeプロジェクト

- 添付のSwiftファイル9本と追加の `RelationLabeler.swift` を
  アプリターゲット `ShinsekiCho` に組み込み
- Bundle ID: `com.naoki-ko.shinsekicho`
- Deployment Target: iOS 17.0
- `ITSAppUsesNonExemptEncryption = false`
- `PhotosPicker` / `PHPicker` のみを使用しているため、写真ライブラリ権限説明
  `NSPhotoLibraryUsageDescription` は不要。Info.plistには追加していない
- 外部ライブラリ、通信処理、追加SDKなし
- UIは日本語。既存の「和帳モダン」テーマ定義は維持
- v3添付の `Models.swift` / `PersonListView.swift` / `PersonDetailView.swift`
  を反映。既存の関係性inverse、写真フォールバック、つながりマップは維持
- 達成度・充実度などのゲーミフィケーション要素は追加していない

## 2. 関係性同期ユニットテスト

| テスト | 結果 |
|---|---|
| `testAddParentChildReflectsBothDirectionsWithoutDuplicates` | PASS |
| `testSetSpouseReflectsBothDirectionsAndClearsOldSpouses` | PASS |
| `testDetachAllRemovesEveryReciprocalRelationship` | PASS |
| `testSiblingsAreDerivedFromSharedParentsAndDeduplicated` | PASS |
| `testRelationshipsPersistAfterContainerRecreation` | PASS |
| `testTwoParentsAndCommonChildPersistAfterContainerRecreation` | PASS |

関係性同期: **6件 PASS / 0件 FAIL**

写真フォールバック:

| テスト | 結果 |
|---|---|
| `testPhotoDecoderReturnsNilForMissingAndCorruptedData` | PASS |
| `testPhotoDecoderAcceptsValidImageData` | PASS |

写真判定: **2件 PASS / 0件 FAIL**

v3モデル・連絡先:

| テスト | 結果 |
|---|---|
| `testHasContactAndContactURLs` | PASS |
| `testV3ProfileFieldsPersistAfterContainerRecreation` | PASS |

v3追加: **2件 PASS / 0件 FAIL**

## 3. FamilyGraphStoreユニットテスト

| テスト | 結果 |
|---|---|
| `testResetAndExpandAddsAllDirectRelationsEdgesAndLevels` | PASS |
| `testExpandingRelatedParentDoesNotDuplicateExistingCommonChild` | PASS |
| `testPreviouslyPlacedNodeLevelsAndSlotsNeverChange` | PASS |
| `testShorterPathReplacesLongerPathWithoutMovingNode` | PASS |
| `testRelationLabelerReturnsSupportedLabels` | PASS |
| `testRelationLabelerLeavesUnsupportedRoutesBlank` | PASS |
| `testFamilyBranchClassificationUsesOnlyTheThreeApprovedBranches` | PASS |
| `testEdgeBranchFollowsTheOutwardFamilyBranch` | PASS |
| `testExpandingTwentyFiveNodesCompletesPromptlyWithoutDuplicates` | PASS |

つながりマップ: **9件 PASS / 0件 FAIL**

ユニットテスト総計: **19件 PASS / 0件 FAIL / 0件 SKIP**

25ノード・24エッジを順次展開する回帰テストは約 **0.006秒** で完了し、
ノードID・エッジIDの重複がないことも確認した。

## 4. UIテスト

| テスト | 主な確認内容 | 結果 |
|---|---|---|
| `testOnboardingValidationTransitionAndRelaunchPersistence` | 空ストア、タブ非表示、未入力時無効、名前入力後の遷移、再起動時スキップ、設定の自分名 | PASS |
| `testSeededGraphExpansionGesturesResetGatheringPhotoAndPersistence` | 6人・関係・写真・集まり、写真フォールバック、3家系色の凡例、未展開5ノード→展開後6ノード、重複なし、ズーム、パン、照準リセット、人物詳細への集まり反映、再起動後のデータ・関係・自分設定 | PASS |
| `testV3RegistrationContactProfileAutoExpansionAndPersistence` | 名前だけで保存、連絡先あり／なし、tel・mailto URL、詳細DisclosureGroup、誕生日・住所・好み・食事配慮、未入力項目非表示、食事配慮行がタブバーより上に収まること、編集時自動展開、再起動後の全フィールド保持 | PASS |

UIテスト総計: **3件 PASS / 0件 FAIL / 0件 SKIP**

ライトモードを起動引数で固定し、展開前5ノードと展開後6ノードを連続取得した。
直系（藍）・配偶者側（深緑）・外側の家系（葡萄）の線とノード縁取り、凡例、
自分の同心円と薄い後光を画像で確認した。破損写真と未設定写真はいずれも
薄い藍色の背景と頭文字へフォールバックし、黒い円は表示されていない。

## 5. ビルド

新しいDerivedDataを使い、iOS Simulator向けDebug構成で
`xcodebuild clean build` を実行。

結果: **BUILD SUCCEEDED**

実行結果:

- `CLEAN SUCCEEDED`
- `BUILD SUCCEEDED`
- 外部パッケージ解決なし

## 6. 実装時に修正した重要点

- 現行SwiftData APIに合わせ、モデルIDを `PersistentIdentifier` に修正
- 親子関係を多対多として永続化できるよう、`parents` と `children` の
  inverseを明示。2人の親と共通の子が再起動後も復元されるテストを追加
- オンボーディング完了時に明示保存し、直後の再起動でも自分設定を保持
- UIテストは通常データと分離した専用SwiftDataストアを使用
- キャンバスのタップとパンを移動距離で判定し、ScrollView内でも
  ノード展開が安定して動くよう修正
- 照準ボタンはスケール・オフセットを即時に初期値へ戻すよう修正
- 写真データの判定を `PersonPhotoSupport` に共通化。`nil`、空データ、
  `UIImage(data:)` が失敗する破損データを一覧・詳細・編集フォーム・
  つながりマップの全画面で同じフォールバックへ通す
- 接続線を3次ベジエ曲線へ変更。配偶者は2.5pt、親子は1.5ptの
  `AppTheme.ruleStrong` とし、色を増やさず線幅で関係を区別
- 自分の背後に `AppTheme.rule` の同心円を3本追加し、未展開ノードを
  opacity 0.92、写真ありノードの縁を1.5ptへ調整
- キャンバス四辺に `AppTheme.paper` へ溶ける固定フェードを追加。
  パン・ズーム対象から分離し、影・外部ライブラリは追加していない
- CanvasをzIndex 0、ノードをzIndex 1に固定。ノード円の最背面を
  不透明な `AppTheme.paperRaised` で塗り、接続線の透けを防止
- `GraphNode.path` と幅優先探索を追加し、表示済みエッジの範囲で
  自分から各人物への最短経路を保持。既存の世代・スロットは変更しない
- `RelationLabeler` で自分・親・配偶者・子・祖父母・孫・兄弟姉妹・
  おじ／おば・甥／姪を判定し、ノード名の下に括弧付きで表示
- UIテスト用の自分を写真未設定にし、人物詳細・一覧・マップすべてで
  SF Symbolsではなく頭文字「山」が表示されることを確認
- `Person` に電話、メール、正式住所、誕生日、好み、食事配慮と
  `hasContact` を追加。指定されたinit引数順を維持し、既存呼び出しも確認
- 登録フォームを常時表示の基本情報と任意の詳細情報に分け、詳細入力済みの
  編集画面ではDisclosureGroupを自動展開。入力中のキーボードを閉じる
  「完了」操作も追加
- 人物詳細に条件付きの連絡先セクションを追加。電話を `tel://`、メールを
  `mailto:` で開き、プロフィールは入力済み項目のみ表示
- アレルギー・食事の配慮は既存の `AppTheme.attention` で強調し、
  この強調のための新色・影・外部ライブラリは追加していない
- `GraphEdgeShape` を追加し、既存の3次ベジエ曲線を維持したまま、追加エッジを
  `trim(from:to:)` と0.4秒の `easeInOut` で描画。追加ノードは0.3倍から
  `spring(response: 0.45, dampingFraction: 0.65)` で登場し、展開元も軽くバウンス
- 最短経路から `FamilyBranch` を判定。直系は既存の藍、配偶者経由は
  `branchForest`、それ以外は `branchPlum` とし、線・ノード縁取りと凡例に限定
- 自分の同心円の外側に、既存の藍をopacity 0.15・blur 20で描いた後光を追加し、
  2秒周期の控えめな `repeatForever(autoreverses: true)` で呼吸させた
- `accessibilityReduceMotion` が有効な場合は登場・線描画を即時化し、バウンスを抑止
- 人物詳細リスト下部へsafe-area余白を追加。UIテストで食事配慮行のmaxYが
  タブバー上端より8pt以上上にあることを座標検証

## 7. tel／mailto の確認範囲

- ユニットテストで電話番号を正規化した `tel://0312345678` と、メール宛先を含む
  `mailto:` URLが生成されることを確認
- UIテストで電話・メールのLinkに上記スキームが設定され、再起動後も保持されることを確認
- 接続可能な物理iPhoneは認識できたが、今回許可されたシミュレータ作業の範囲を越えて
  端末へインストール・OSアプリ起動する操作は実施していない。実機確認時は、署名済み
  Debugビルドを接続iPhoneへ実行し、人物詳細の電話・メールを順にタップして、電話確認
  画面とメール作成画面に番号・宛先が渡ることを確認する（発信・送信前にキャンセル）

## 8. つながりマップ表示の追加調整（2026-07-27）

- blurを含むマップ全体を `compositingGroup()` で最終合成した後、420ptの
  キャンバス境界で再度 `clipped()`。Listをスクロールしても自己ノードの後光が
  見出しカード領域へ描画漏れしないことを、中央・上端付近の画像で確認
- 家系色の凡例を、ドット列から「直系」「配偶者側」「外側の家系」の3カプセルへ変更。
  各カプセルは家系色opacity 0.12の背景、`AppTheme.rule` 1pt枠、家系色文字で構成
- ノード円へ家系色opacity 0.08を重ね、写真あり／なしの双方でまとまりを視認可能にした。
  自分ノードだけは `AppTheme.attention` opacity 0.08を維持。新色は追加していない
- マップ専用UIテスト: **1件 PASS / 0件 FAIL**
- 最終ユニットテスト: **19件 PASS / 0件 FAIL / 0件 SKIP**

## 成果物

- Xcodeプロジェクト: `ShinsekiCho.xcodeproj`
- 最終ユニットテスト結果: `TestResults/UnitTests-LegendGlowClip-Final.xcresult`
- 最終UIテスト結果: `TestResults/UITests-BranchAnimation-Final.xcresult`
- 表示調整後マップUIテスト: `TestResults/UITests-LegendGlowClip.xcresult`
- クリーンビルド: `TestResults/DerivedData-CleanBuild-BranchAnimation`
- ライトモード画像:
  - `Screenshots/Onboarding-Light.png`
  - `Screenshots/ConnectionMap-6Nodes-Light.png`
  - `Screenshots/PersonForm-Basic-Light.png`
  - `Screenshots/PersonForm-Details-Light.png`
  - `Screenshots/PersonDetail-Enriched-Light.png`
  - `Screenshots/PersonDetail-Enriched-Lower-Light.png`
  - `Screenshots/ConnectionMap-BranchColors-Before-Light.png`
  - `Screenshots/ConnectionMap-BranchColors-After-Light.png`
  - `Screenshots/PersonDetail-Dietary-Clear-Light.png`
  - `Screenshots/ConnectionMap-CapsuleLegend-Lower-Light.png`
  - `Screenshots/ConnectionMap-CapsuleLegend-Centered-Light.png`
  - `Screenshots/ConnectionMap-GlowClipped-Upper-Light.png`

途中の失敗結果と診断添付も削除せず、原因追跡用に保存している。
