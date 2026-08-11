# Phase 10.4 Performance Validation

実施日: 2026-08-12
Baseline: `b2bfb0590b8037844a428d047e97dda75933f294`
Simulator: iPhone 17 Pro / iOS 26.5 / 1206×2622
Configuration: Unit・UIはDebug、clean buildはRelease

## Fixture

`PerformanceFixtureBuilder`が乱数や現在日時に依存せず、すべての関係を
`RelationshipManager`経由で構築する。Releaseでは`#if DEBUG`によりfixtureと
launch argument処理を除外する。

| Size | Person | Photo | Gathering | Attendees / Gathering |
|---|---:|---:|---:|---:|
| Small | 10 | 4 | 3 | 10 |
| Medium | 50 | 20 | 10 | 20〜29 |
| Stress | 100 | 50 | 20 | 20〜30 |

父母、配偶者、兄弟姉妹、共同子、複数世代、配偶者側を含む。写真は4種類の
小さな有効PNGを再利用する。Unit Testで双方向整合、親2人上限、配偶者の
双方向性、ancestry cycleなし、同一sizeの決定性を検証した。

## Baseline metrics

時間はiPhone 17 Pro Simulator上の実測。Unit値は処理本体、UI値はXCUIの入力・
待機・画面アニメーションを含むend-to-end値であり、両者を直接比較しない。

| Scenario | 10 | 50 | 100 | Classification |
|---|---:|---:|---:|---|
| Person List | not measured | 3.75s UI表示 | scroll smoke PASS（時間未計測） | ACCEPTABLE |
| Search（6 queries合計） | 0.020s | 0.107s | 0.309s | PASS |
| Search UI | not measured | 3.82s | 3.87s | ACCEPTABLE |
| FamilyGraph snapshot | not measured | not measured | 0.458s / 100 nodes | PASS |
| Backup Export | 0.0039s | 0.0022s | 0.0043s | PASS |
| Backup Restore | 0.0028s | 0.0115s | 0.0221s | PASS |
| Backup JSON | 10,325B | 52,403B | 110,544B | PASS |
| Memory | not measured | not measured | Debug Simulator RSS snapshot 249,552KB | NEEDS FOLLOW-UP |

Cold launch（50人、canvas表示まで）は3回とも成功: 3.79s / 3.36s / 3.31s。
UI Test用TrialManagerはネットワークを使わない注入実装のため、App Store entitlement
通信時間はこの値に含まれない。

## Scenario results

- Person Detail: 写真付き人物10人を連続開閉しPASS（XCUI全体78.01s）。クラッシュ、
  操作不能なし。
- FamilyGraph: 100 nodeのrender snapshotを全展開し、43 nodeだけが160pt overscan内で
  visible。CoupleKnot dictionaryと描画segmentを確認。100人DBでpan、pinch、resetを
  含むUI smokeがPASS。
- Photo cache: 写真50人を5巡（250要求）してdecoder呼び出しは50回。frameごとの
  再decodeなし。
- Gathering / Prep: 20件・各20〜30人のstress fixtureで一覧、詳細、予習開始、次の人物
  操作までPASS（独立UI Test 11.43s）。
- Backup: 10/50/100すべてexport→validate→replace restoreを実施。Person、Gathering、
  parent-child edge、spouse edge、self、photo数が一致。
- Merge / relationship correction: 100人に対する3種類の候補判定は0.0009s、duplicate
  mergeは0.0023s。統合後Person数は100で、既存semanticsを維持。
- Accessibility regression: Phase 10.3のXXXL Dynamic Type、Dark Mode、graph / prepの
  accessibility metadataの3 UI TestがPASS。

## Instruments and runtime limitations

`xctrace`でTime Profilerをlaunch方式とattach方式の両方で10秒記録したが、生成traceの
exportがどちらも`Document Missing Template Error`で失敗した。このため次は数値を
推測せず未計測とする。

- Time Profilerのcall tree / main-thread占有率
- Core AnimationのFPS / hitch数
- Allocations推移とLeaks
- 30〜60秒のPower Profiler / thermal

100人Debugアプリの静止時RSSスナップショットは249,552KBだったが、Simulator・Debugの
単一点でありRelease実機のGate値には使用しない。

一度、100人の地図操作直後にGathering操作まで連結したXCUI Testがautomation側で
約15分停止した。地図stressとGathering stressを独立させると、それぞれ29.998sと
11.431sで再現性をもってPASSした。production freezeを示す再現はなく、test isolation
の問題として扱う。

## Classification

| Area | Result | Reason |
|---|---|---|
| Launch | ACCEPTABLE | 3 cold launches完了、停止なし |
| Person List / Detail | ACCEPTABLE | 100人scroll smoke、写真人物10人連続開閉PASS |
| Search | PASS | 100人・6 queriesで0.31s、複合検索UIもPASS |
| FamilyGraph | PASS | snapshot/culling/cacheと100人DB UI操作PASS |
| Gathering / Prep | PASS | 20件・20〜30 attendeesでPASS |
| Backup round-trip | PASS | 100人/50写真/20件を0.03s未満で復元、整合一致 |
| Merge / Relation | PASS | 100人候補評価と1 merge成功 |
| Memory / Leaks / FPS / Energy | NEEDS FOLLOW-UP | xctrace export不能、実機未計測 |

Release blockerは0件。推測ベースのproduction最適化は行っていない。

## Human Gate / Post-release follow-up

1. 物理iPhoneのRelease buildでTime Profiler、Animation Hitches、Allocations、Leaksを実行。
2. launch→100人一覧→全展開graph→写真人物10人→一覧復帰のmemory推移を採取。
3. graphを60秒操作してFPS hitch、継続CPU、Energy、thermalを確認。
4. 実機のStoreKit entitlementを含むcold launchを3回計測。

上記は `Human Gate — physical device performance` として残す。

## Automated verification

- PerformanceFixtureTests: 7 / 7 PASS
- All Unit Tests: 304 / 304 PASS
  - 既知のStoreKit daemon依存
    `testStoreKitConfigurationLoadsYenProductAndCompletesPurchase`のみ従来どおり除外
- Performance UI:
  - medium cold launch 3 runs PASS
  - medium list/search/detail/graph PASS
  - medium 10 photo-person details PASS
  - stress list/search/graph PASS
  - stress Gathering Prep PASS
- Phase 10.3 Accessibility UI regression: 3 / 3 PASS
- Release clean build: PASS
