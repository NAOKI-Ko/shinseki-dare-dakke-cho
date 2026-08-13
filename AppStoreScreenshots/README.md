# App Store画像制作レポート

制作日: 2026-08-13

対象: 親戚だれだっけ帳 2.0 (11)

端末: iPhone 16 Pro Max Simulator / iOS 26.5 / ライトモード

出力: 1320 × 2868 px、RGB PNG、アルファなし

## 制作方針

「家系図アプリ」ではなく、法事や結婚式で「あの人誰だっけ？」をなくす親戚記憶アプリとして構成した。実装済みの実画面を主役に、生成りの和紙、深い藍、朱、深緑、葡萄、淡金の罫線で和モダンに統一している。アプリUIの描き直しや未実装機能の追加は行っていない。

## 6枚の構成

1. `01_memory-summary.png`
   - 主コピー: 「あの人誰だっけ？」を、すぐ確認。
   - 画面: 佐藤健太の人物詳細とMemory Summary
2. `02_family-graph.png`
   - 主コピー: 親戚のつながりが、ひと目でわかる。
   - 画面: 配偶者・共同子・夫婦の結び目を含むFamilyGraph
3. `03_gathering-prep.png`
   - 主コピー: 法事や結婚式の前に、会う人だけ予習。
   - 画面: 集まり前予習モード
4. `04_search.png`
   - 主コピー: 名前を忘れても、手がかりから探せる。
   - 画面: 集まり名「親族の集まり」で人物を検索した結果
5. `05_person-memory.png`
   - 主コピー: 前に話したことまで、思い出せる。
   - 画面: 会話メモと出席した集まりが見える人物詳細
6. `06_backup.png`
   - 主コピー: 大切な記録は、自分でバックアップ。
   - 画面: バックアップ復元プレビューと置換警告

## Apple提出仕様

- Apple公式App Store Connectの現行仕様に従い、6.9インチiPhoneで受理される `1320 × 2868` pxを採用。
- 1〜10枚の範囲内で6枚を制作。
- PNG形式、アルファチャンネルなし。
- このアプリは `TARGETED_DEVICE_FAMILY = 1` のiPhone専用であるため、iPad用画像は制作していない。

公式資料:

- https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications
- https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots

## 成果物

- 完成画像: `final/iphone/`
- コンタクトシート: `preview/contact-sheet.png`
- 生スクリーンショット: `/tmp/ShinsekiChoAppStoreImages/raw/iphone/`
- 再生成スクリプト: `scripts/create_app_store_images.py`

生スクリーンショットはXCUITestから取得した実画面。使用データはDEBUG限定の架空fixtureで、Release binaryには含まれない。
