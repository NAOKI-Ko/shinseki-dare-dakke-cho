import XCTest

final class ShinsekiChoUITests: XCTestCase {
  private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  private func launch(
    reset: Bool = true,
    seed: Bool = false,
    additionalArguments: [String] = []
  ) -> XCUIApplication {
    let app = XCUIApplication()
    var arguments: [String] = []
    arguments.append(contentsOf: ["-ui-testing", "-AppleInterfaceStyle", "Light"])
    if reset { arguments.append("-ui-testing-reset") }
    if seed { arguments.append("-ui-testing-seed") }
    arguments.append(contentsOf: additionalArguments)
    app.launchArguments = arguments
    app.launch()
    return app
  }

  private func reveal(
    _ element: XCUIElement,
    in app: XCUIApplication,
    maxSwipes: Int = 10
  ) {
    for _ in 0..<maxSwipes {
      var visibleBottom = app.frame.maxY - 12
      let keyboardToolbarButton = app.buttons["personForm.dismissKeyboard"]
      if keyboardToolbarButton.exists {
        visibleBottom = min(visibleBottom, keyboardToolbarButton.frame.minY - 8)
      } else if app.keyboards.firstMatch.exists {
        visibleBottom = min(visibleBottom, app.keyboards.firstMatch.frame.minY - 8)
      }
      if app.tabBars.firstMatch.exists {
        visibleBottom = min(visibleBottom, app.tabBars.firstMatch.frame.minY - 8)
      }
      if element.exists,
        element.isHittable,
        element.frame.minY >= 120,
        element.frame.maxY <= visibleBottom
      {
        return
      }
      app.swipeUp()
    }
  }

  private func keepScreenshot(
    _ app: XCUIApplication,
    name: String
  ) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  private func dismissKeyboard(in app: XCUIApplication) {
    let doneButton = app.buttons["personForm.dismissKeyboard"]
    if doneButton.waitForExistence(timeout: 2) {
      doneButton.tap()
    }
    XCTAssertFalse(app.keyboards.firstMatch.exists)
  }

  private func showList(in app: XCUIApplication) {
    let listSegment = app.buttons["一覧"]
    XCTAssertTrue(listSegment.waitForExistence(timeout: 5))
    listSegment.tap()
  }

  private func showMap(in app: XCUIApplication) {
    let mapSegment = app.buttons["つながり"]
    XCTAssertTrue(mapSegment.waitForExistence(timeout: 5))
    mapSegment.tap()
  }

  func testOnboardingValidationTransitionAndRelaunchPersistence() {
    var app = launch()
    let nameField = app.textFields["onboarding.nameField"]
    let startButton = app.buttons["onboarding.startButton"]

    XCTAssertTrue(nameField.waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["親戚"].exists)
    XCTAssertFalse(startButton.isEnabled)
    let onboardingScreenshot = XCTAttachment(screenshot: app.screenshot())
    onboardingScreenshot.name = "オンボーディング_ライト"
    onboardingScreenshot.lifetime = .keepAlways
    add(onboardingScreenshot)

    nameField.tap()
    nameField.typeText("UIテスト 太郎")
    XCTAssertTrue(startButton.isEnabled)
    startButton.tap()

    let firstGuidePage = element("onboarding.guide.page1", in: app)
    XCTAssertTrue(firstGuidePage.waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["onboarding.guide.skipButton"].exists)
    XCTAssertFalse(app.buttons["親戚"].exists)

    app.buttons["onboarding.guide.nextButton"].tap()
    let secondGuidePage = element("onboarding.guide.page2", in: app)
    XCTAssertTrue(secondGuidePage.waitForExistence(timeout: 5))
    let completeButton = app.buttons["onboarding.guide.completeButton"]
    XCTAssertTrue(completeButton.waitForExistence(timeout: 5))
    completeButton.tap()

    XCTAssertTrue(app.buttons["親戚"].waitForExistence(timeout: 5))
    XCTAssertFalse(nameField.exists)
    app.terminate()

    app = launch(reset: false)
    XCTAssertTrue(app.buttons["親戚"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.textFields["onboarding.nameField"].exists)
    app.buttons["設定"].tap()
    let selfName = element("settings.selfName", in: app)
    XCTAssertTrue(selfName.waitForExistence(timeout: 5))
    XCTAssertTrue(selfName.label.contains("UIテスト 太郎"))
  }

  func testOnboardingGuideSkipTransitionsToTabs() {
    var app = launch()
    let nameField = app.textFields["onboarding.nameField"]
    XCTAssertTrue(nameField.waitForExistence(timeout: 5))

    nameField.tap()
    nameField.typeText("スキップ 太郎")
    app.buttons["onboarding.startButton"].tap()

    let skipButton = app.buttons["onboarding.guide.skipButton"]
    XCTAssertTrue(skipButton.waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["親戚"].exists)

    // 名前は保存済みでも、説明を終えていなければ次回起動で案内を再開する。
    app.terminate()
    app = launch(reset: false)
    let resumedSkipButton = app.buttons["onboarding.guide.skipButton"]
    XCTAssertTrue(resumedSkipButton.waitForExistence(timeout: 5))
    resumedSkipButton.tap()

    XCTAssertTrue(app.buttons["親戚"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["onboarding.guide.skipButton"].exists)
  }

  func testSeededGraphExpansionGesturesResetGatheringPhotoAndPersistence() {
    var app = launch(
      seed: true,
      additionalArguments: ["-ui-testing-family-graph-ux"]
    )
    XCTAssertTrue(app.buttons["親戚"].waitForExistence(timeout: 5))
    showList(in: app)
    let selfCell = element("person.cell.山田 太郎", in: app)
    XCTAssertTrue(selfCell.waitForExistence(timeout: 5))
    XCTAssertEqual(selfCell.value as? String, "写真なし")
    XCTAssertEqual(
      element("person.cell.佐藤 美咲", in: app).value as? String,
      "写真なし"
    )
    XCTAssertEqual(
      element("person.cell.山田 花子", in: app).value as? String,
      "写真なし"
    )
    selfCell.tap()
    let selfInitial = element("personDetail.photo.initial", in: app)
    XCTAssertTrue(selfInitial.waitForExistence(timeout: 5))
    XCTAssertEqual(selfInitial.label, "山")
    let scrollStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.72))
    let scrollEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.22))
    scrollStart.press(forDuration: 0.05, thenDragTo: scrollEnd)

    let canvas = element("connectionMap.canvas", in: app)
    XCTAssertTrue(canvas.waitForExistence(timeout: 5))
    let introCompleted = expectation(
      for: NSPredicate { object, _ in
        ((object as? XCUIElement)?.value as? String)?.hasPrefix("完了|") == true
      },
      evaluatedWith: canvas
    )
    wait(for: [introCompleted], timeout: 3)
    func mapElement(_ identifier: String) -> XCUIElement {
      canvas.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
    XCTAssertTrue(mapElement("connectionMap.node.山田 太郎").exists)
    XCTAssertTrue(mapElement("connectionMap.node.山田 一郎").exists)
    XCTAssertTrue(mapElement("connectionMap.node.山田 花子").exists)
    XCTAssertTrue(mapElement("connectionMap.node.佐藤 美咲").exists)
    XCTAssertTrue(mapElement("connectionMap.node.山田 葵").exists)
    XCTAssertFalse(mapElement("connectionMap.node.山田 次郎").exists)
    let legend = mapElement("connectionMap.legend")
    XCTAssertTrue(legend.exists)
    XCTAssertTrue(legend.label.contains("直系"))
    XCTAssertTrue(legend.label.contains("配偶者側"))
    XCTAssertTrue(legend.label.contains("外側の家系"))
    let selfNode = mapElement("connectionMap.node.山田 太郎")
    XCTAssertEqual(selfNode.frame.midX, app.frame.midX, accuracy: 2)
    let resetButton = app.buttons["connectionMap.detail.resetButton"]
    XCTAssertTrue(resetButton.waitForExistence(timeout: 3))
    resetButton.tap()
    let resetReferenceFrame = selfNode.frame

    let beforeExpansion = XCTAttachment(screenshot: app.screenshot())
    beforeExpansion.name = "つながりマップ_展開前_5ノード_ライト"
    beforeExpansion.lifetime = .keepAlways
    add(beforeExpansion)

    let father = mapElement("connectionMap.node.山田 一郎")
    XCTAssertTrue((father.value as? String)?.hasPrefix("未展開") == true)
    let appFrame = app.frame
    let mapTop = app.staticTexts["つながり"].frame.maxY
    app.coordinate(
      withNormalizedOffset: CGVector(
        dx: father.frame.midX / appFrame.width,
        dy: (mapTop + 130.0) / appFrame.height
      )
    ).tap()
    XCTAssertTrue(mapElement("connectionMap.node.山田 次郎").waitForExistence(timeout: 3))
    XCTAssertTrue((father.value as? String)?.hasPrefix("展開済み") == true)
    let preGestureSelfFrame = selfNode.frame
    canvas.pinch(withScale: 1.4, velocity: 1)
    canvas.swipeLeft()
    XCTAssertGreaterThan(abs(selfNode.frame.midX - preGestureSelfFrame.midX), 10)
    resetButton.tap()
    let viewportReset = expectation(
      for: NSPredicate { _, _ in
        let resetFrame = selfNode.frame
        let canvasValue = canvas.value as? String ?? ""
        return abs(resetFrame.midX - resetReferenceFrame.midX) <= 2
          && canvasValue.contains("scale:1.00")
      },
      evaluatedWith: selfNode
    )
    wait(for: [viewportReset], timeout: 3)
    XCTAssertEqual(selfNode.frame.midX, resetReferenceFrame.midX, accuracy: 2)
    XCTAssertTrue((canvas.value as? String)?.contains("scale:1.00") == true)

    let desiredMapTop: CGFloat = 150
    let pageAdjustment = desiredMapTop - app.staticTexts["つながり"].frame.maxY
    if abs(pageAdjustment) > 5 {
      let startY: CGFloat = 0.45
      let endY = min(max(startY + pageAdjustment / appFrame.height, 0.15), 0.75)
      app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: startY))
        .press(
          forDuration: 0.05,
          thenDragTo: app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.02, dy: endY)
          )
        )
    }

    let mapScreenshot = XCTAttachment(screenshot: app.screenshot())
    mapScreenshot.name = "つながりマップ_6ノード_ライト"
    mapScreenshot.lifetime = .keepAlways
    add(mapScreenshot)

    // キャンバスを画面上端近くまで送った状態でも、blurを含む後光が
    // キャンバス外（ナビゲーション／見出し領域）へ漏れないことを画像確認する。
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.68))
      .press(
        forDuration: 0.05,
        thenDragTo: app.coordinate(
          withNormalizedOffset: CGVector(dx: 0.02, dy: 0.55)
        )
      )
    let clippedMapScreenshot = XCTAttachment(screenshot: app.screenshot())
    clippedMapScreenshot.name = "つながりマップ_上端クリップ_6ノード_ライト"
    clippedMapScreenshot.lifetime = .keepAlways
    add(clippedMapScreenshot)

    app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.72))
      .press(
        forDuration: 0.05,
        thenDragTo: app.coordinate(
          withNormalizedOffset: CGVector(dx: 0.02, dy: 0.35)
        )
      )
    XCTAssertTrue(app.staticTexts["祖母の一周忌"].waitForExistence(timeout: 5))

    app.navigationBars.buttons.element(boundBy: 0).tap()
    app.buttons["集まり"].tap()
    XCTAssertTrue(app.staticTexts["祖母の一周忌"].waitForExistence(timeout: 5))
    app.staticTexts["祖母の一周忌"].tap()
    XCTAssertTrue(app.staticTexts["山田 太郎"].waitForExistence(timeout: 3))

    app.terminate()
    app = launch(reset: false)
    XCTAssertTrue(app.buttons["親戚"].waitForExistence(timeout: 5))
    showList(in: app)
    XCTAssertTrue(element("person.cell.山田 太郎", in: app).waitForExistence(timeout: 5))
    app.buttons["集まり"].tap()
    XCTAssertTrue(app.staticTexts["祖母の一周忌"].waitForExistence(timeout: 5))
    app.buttons["親戚"].tap()
    showList(in: app)
    element("person.cell.山田 太郎", in: app).tap()
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.72))
      .press(
        forDuration: 0.05,
        thenDragTo: app.coordinate(
          withNormalizedOffset: CGVector(dx: 0.02, dy: 0.22)
        )
      )
    XCTAssertTrue(element("connectionMap.node.山田 一郎", in: app).waitForExistence(timeout: 5))
    app.navigationBars.buttons.element(boundBy: 0).tap()
    app.buttons["設定"].tap()
    XCTAssertTrue(element("settings.selfName", in: app).label.contains("山田 太郎"))
  }

  func testV3RegistrationContactProfileAutoExpansionAndPersistence() {
    var app = launch(seed: true)
    XCTAssertTrue(app.buttons["親戚"].waitForExistence(timeout: 5))
    showList(in: app)

    // 詳細・連絡先が空でも、名前だけで保存できる。
    app.buttons["人物を追加"].tap()
    let nameField = element("personForm.name", in: app)
    XCTAssertTrue(nameField.waitForExistence(timeout: 5))
    nameField.tap()
    nameField.typeText("連絡先なし 美子")
    app.buttons["personForm.saveButton"].tap()

    let basicOnlyCell = element("person.cell.連絡先なし 美子", in: app)
    XCTAssertTrue(basicOnlyCell.waitForExistence(timeout: 5))
    basicOnlyCell.tap()
    XCTAssertTrue(element("personDetail.profileHeader", in: app).waitForExistence(timeout: 5))
    XCTAssertFalse(element("personDetail.contactHeader", in: app).exists)
    app.navigationBars.buttons.element(boundBy: 0).tap()

    // 基本情報と図鑑の詳細情報をフォームから登録する。
    app.buttons["人物を追加"].tap()
    let zukanName = element("personForm.name", in: app)
    XCTAssertTrue(zukanName.waitForExistence(timeout: 5))
    zukanName.tap()
    zukanName.typeText("図鑑 花子")

    let kana = element("personForm.kana", in: app)
    kana.tap()
    kana.typeText("ずかん はなこ")
    dismissKeyboard(in: app)

    let relation = element("personForm.relationNote", in: app)
    reveal(relation, in: app)
    relation.tap()
    relation.typeText("いとこ")
    dismissKeyboard(in: app)

    let phone = element("personForm.phone", in: app)
    reveal(phone, in: app)
    phone.tap()
    phone.typeText("03-1234-5678")
    dismissKeyboard(in: app)

    let email = element("personForm.email", in: app)
    email.tap()
    email.typeText("hanako@example.com")
    dismissKeyboard(in: app)

    let livingArea = element("personForm.livingArea", in: app)
    reveal(livingArea, in: app)
    livingArea.tap()
    livingArea.typeText("横浜")

    dismissKeyboard(in: app)
    keepScreenshot(app, name: "人物登録フォーム_基本情報_ライト")

    let detailsDisclosure = element("personForm.detailsDisclosure", in: app)
    reveal(detailsDisclosure, in: app)
    detailsDisclosure.tap()

    let postalAddress = element("personForm.postalAddress", in: app)
    reveal(postalAddress, in: app)
    XCTAssertTrue(postalAddress.waitForExistence(timeout: 3))
    postalAddress.tap()
    postalAddress.typeText("〒100-0001 東京都千代田区1-1")
    dismissKeyboard(in: app)

    let birthdayToggle = element("personForm.birthdayToggle", in: app)
    reveal(birthdayToggle, in: app)
    birthdayToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
    XCTAssertEqual(birthdayToggle.value as? String, "1")

    let favorites = element("personForm.favorites", in: app)
    reveal(favorites, in: app)
    favorites.tap()
    favorites.typeText("和菓子と猫")
    dismissKeyboard(in: app)

    let dietaryNotes = element("personForm.dietaryNotes", in: app)
    reveal(dietaryNotes, in: app)
    dietaryNotes.tap()
    dietaryNotes.typeText("落花生アレルギー")
    dismissKeyboard(in: app)

    let memo = element("personForm.memo", in: app)
    reveal(memo, in: app)
    memo.tap()
    memo.typeText("次は旅行の話を聞く")
    dismissKeyboard(in: app)
    keepScreenshot(app, name: "人物登録フォーム_詳細展開_ライト")
    app.buttons["personForm.saveButton"].tap()

    let zukanCell = element("person.cell.図鑑 花子", in: app)
    XCTAssertTrue(zukanCell.waitForExistence(timeout: 5))
    zukanCell.tap()

    let contactHeader = element("personDetail.contactHeader", in: app)
    XCTAssertTrue(contactHeader.waitForExistence(timeout: 5))
    let phoneLink = element("personDetail.phoneLink", in: app)
    XCTAssertEqual(phoneLink.value as? String, "tel://0312345678")
    let emailLink = element("personDetail.emailLink", in: app)
    XCTAssertTrue((emailLink.value as? String)?.contains("mailto:") == true)

    let birthday = element("personDetail.birthday", in: app)
    reveal(birthday, in: app, maxSwipes: 4)
    XCTAssertTrue(birthday.exists)
    let postal = element("personDetail.postalAddress", in: app)
    reveal(postal, in: app, maxSwipes: 4)
    XCTAssertTrue(postal.exists)
    keepScreenshot(app, name: "人物詳細_連絡先プロフィール上部_ライト")

    let favorite = element("personDetail.favorites", in: app)
    reveal(favorite, in: app, maxSwipes: 4)
    XCTAssertTrue(favorite.exists)
    let dietary = element("personDetail.dietaryNotes", in: app)
    reveal(dietary, in: app, maxSwipes: 4)
    XCTAssertTrue(dietary.exists)
    XCTAssertEqual(dietary.value as? String, "AppTheme.attention")
    XCTAssertLessThan(dietary.frame.maxY, app.tabBars.firstMatch.frame.minY - 8)
    XCTAssertFalse(element("personDetail.lastMet", in: app).exists)
    keepScreenshot(app, name: "人物詳細_プロフィール下部_ライト")

    // 詳細項目が保存済みなら、編集時のDisclosureGroupは自動展開される。
    app.buttons["編集"].tap()
    let editDisclosure = element("personForm.detailsDisclosure", in: app)
    reveal(editDisclosure, in: app)
    XCTAssertTrue(editDisclosure.waitForExistence(timeout: 5))
    XCTAssertEqual(editDisclosure.value as? String, "展開中")
    XCTAssertTrue(element("personForm.postalAddress", in: app).exists)
    app.buttons["キャンセル"].tap()

    // 再起動後もv3の全新規フィールドが保持される。
    app.terminate()
    app = launch(reset: false)
    XCTAssertTrue(app.buttons["親戚"].waitForExistence(timeout: 5))
    showList(in: app)
    let persistedCell = element("person.cell.図鑑 花子", in: app)
    XCTAssertTrue(persistedCell.waitForExistence(timeout: 5))
    persistedCell.tap()
    XCTAssertTrue(element("personDetail.contactHeader", in: app).waitForExistence(timeout: 5))
    XCTAssertEqual(
      element("personDetail.phoneLink", in: app).value as? String,
      "tel://0312345678"
    )
    let persistedDietary = element("personDetail.dietaryNotes", in: app)
    let persistedBirthday = element("personDetail.birthday", in: app)
    reveal(persistedBirthday, in: app, maxSwipes: 4)
    XCTAssertTrue(persistedBirthday.exists)
    let persistedPostal = element("personDetail.postalAddress", in: app)
    reveal(persistedPostal, in: app, maxSwipes: 4)
    XCTAssertTrue(persistedPostal.exists)
    let persistedFavorites = element("personDetail.favorites", in: app)
    reveal(persistedFavorites, in: app, maxSwipes: 4)
    XCTAssertTrue(persistedFavorites.exists)
    reveal(persistedDietary, in: app, maxSwipes: 4)
    XCTAssertTrue(persistedDietary.exists)
  }

  func testHomeDefaultsToMapSwitchesListSearchesAndRestoresMap() {
    let app = launch(seed: true)

    let tabBar = app.tabBars.firstMatch
    XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
    XCTAssertEqual(tabBar.buttons.count, 3)
    XCTAssertTrue(tabBar.buttons["親戚"].exists)
    XCTAssertTrue(tabBar.buttons["集まり"].exists)
    XCTAssertTrue(tabBar.buttons["設定"].exists)
    XCTAssertFalse(tabBar.buttons["地図"].exists)

    // 初期表示は、独立タブではなく「親戚」内のつながりセグメント。
    XCTAssertTrue(app.navigationBars["つながり"].waitForExistence(timeout: 5))
    XCTAssertTrue(element("connectionMap.home.canvas", in: app).waitForExistence(timeout: 5))
    XCTAssertTrue(element("connectionMap.node.山田 太郎", in: app).exists)
    XCTAssertTrue(app.searchFields.firstMatch.exists)
    keepScreenshot(app, name: "Home_01_起動直後のつながり_ライト")

    showList(in: app)
    XCTAssertTrue(app.navigationBars["一覧"].waitForExistence(timeout: 5))
    XCTAssertTrue(element("person.cell.山田 太郎", in: app).waitForExistence(timeout: 5))
    XCTAssertTrue(element("person.cell.佐藤 美咲", in: app).exists)
    keepScreenshot(app, name: "Home_02_一覧セグメント_ライト")

    // つながりを選んだ状態から検索を始めると、一覧へ自動切替される。
    showMap(in: app)
    XCTAssertTrue(element("connectionMap.home.canvas", in: app).waitForExistence(timeout: 5))
    let searchField = app.searchFields.firstMatch
    searchField.tap()
    searchField.typeText("佐藤")
    XCTAssertTrue(element("person.cell.佐藤 美咲", in: app).waitForExistence(timeout: 5))
    XCTAssertTrue(element("person.cell.佐藤 健太", in: app).exists)
    XCTAssertFalse(element("person.cell.山田 太郎", in: app).exists)
    let searchKey = app.keyboards.buttons["検索"]
    if searchKey.exists {
      searchKey.tap()
    } else if app.keyboards.firstMatch.exists {
      // iOSの言語・キーボード構成によってReturnキーのラベルが変わるため、
      // 検索フィールドへReturnを直接送り、テストが環境依存で止まらないようにする。
      searchField.typeText("\n")
    }
    XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
    keepScreenshot(app, name: "Home_03_検索で佐藤に絞り込み_ライト")

    // クリアすると、検索前に選んでいたつながりへ戻る。
    let clearButton = searchField.buttons.firstMatch
    XCTAssertTrue(clearButton.waitForExistence(timeout: 3))
    clearButton.tap()
    XCTAssertTrue(element("connectionMap.home.canvas", in: app).waitForExistence(timeout: 5))
    XCTAssertTrue(element("connectionMap.node.山田 太郎", in: app).exists)
  }

  func testConnectionLayersKeepEdgesBehindOpaqueNodes() {
    let app = launch(seed: true)
    XCTAssertTrue(app.navigationBars["つながり"].waitForExistence(timeout: 5))

    let edgeLayer = element("connectionMap.edgeLayer", in: app)
    let nodeLayer = element("connectionMap.nodeLayer", in: app)
    XCTAssertTrue(edgeLayer.waitForExistence(timeout: 5))
    XCTAssertTrue(nodeLayer.waitForExistence(timeout: 5))
    XCTAssertEqual(edgeLayer.value as? String, "最背面")
    XCTAssertEqual(nodeLayer.value as? String, "最前面")

    for name in ["山田 太郎", "山田 一郎", "山田 花子", "山田 葵"] {
      XCTAssertTrue(element("connectionMap.node.\(name)", in: app).exists)
    }

    let canvas = element("connectionMap.home.canvas", in: app)
    canvas.pinch(withScale: 1.08, velocity: 0.1)
    keepScreenshot(app, name: "Home_04_同姓ノード拡大_線は最背面_ライト")
  }

  func testFullScreenMapContextMenuQuickChildAndLaterEditing() {
    let app = launch(seed: true)
    XCTAssertTrue(app.navigationBars["つながり"].waitForExistence(timeout: 5))
    let canvas = element("connectionMap.home.canvas", in: app)
    XCTAssertTrue(canvas.waitForExistence(timeout: 5))
    let selfNode = element("connectionMap.node.山田 太郎", in: app)
    XCTAssertTrue(selfNode.waitForExistence(timeout: 5))
    XCTAssertTrue(element("connectionMap.node.佐藤 美咲", in: app).exists)
    keepScreenshot(app, name: "Home_つながり_フルスクリーン_ライト")

    selfNode.press(forDuration: 1.2)
    XCTAssertTrue(app.buttons["詳細を見る"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.buttons["子を追加"].exists)
    XCTAssertFalse(app.buttons["配偶者を追加"].exists)
    XCTAssertFalse(app.buttons["親を追加"].exists)
    keepScreenshot(app, name: "Home_つながり_長押しメニュー_ライト")

    app.buttons["子を追加"].tap()
    let nameField = element("quickRelative.name", in: app)
    XCTAssertTrue(nameField.waitForExistence(timeout: 3))
    nameField.typeText("法事で会った 光")
    app.buttons["quickRelative.save"].tap()

    let newNode = element("connectionMap.node.法事で会った 光", in: app)
    XCTAssertTrue(newNode.waitForExistence(timeout: 5))
    keepScreenshot(app, name: "Home_つながり_子を即時追加_ライト")

    showList(in: app)
    let newCell = element("person.cell.法事で会った 光", in: app)
    reveal(newCell, in: app, maxSwipes: 12)
    XCTAssertTrue(newCell.waitForExistence(timeout: 5))
    newCell.tap()
    XCTAssertTrue(app.buttons["編集"].waitForExistence(timeout: 5))
    app.buttons["編集"].tap()
    let phoneField = element("personForm.phone", in: app)
    reveal(phoneField, in: app)
    XCTAssertTrue(phoneField.waitForExistence(timeout: 3))
    phoneField.tap()
    phoneField.typeText("090-9999-0000")
    dismissKeyboard(in: app)
    app.buttons["personForm.saveButton"].tap()
    XCTAssertTrue(element("personDetail.phoneLink", in: app).waitForExistence(timeout: 5))
  }

  func testDirectKentaDetailAutoExpandsAndKeepsInitialFallbacks() {
    let app = launch(seed: true)
    showList(in: app)
    let kentaCell = element("person.cell.佐藤 健太", in: app)
    XCTAssertTrue(kentaCell.waitForExistence(timeout: 5))
    XCTAssertEqual(kentaCell.value as? String, "写真なし")
    XCTAssertEqual(
      element("person.cell.佐藤 美咲", in: app).value as? String,
      "写真なし"
    )
    kentaCell.tap()

    let canvas = element("connectionMap.canvas", in: app)
    reveal(canvas, in: app, maxSwipes: 8)
    XCTAssertTrue(canvas.waitForExistence(timeout: 5))
    for name in ["山田 太郎", "佐藤 美咲", "佐藤 修一", "佐藤 健太"] {
      XCTAssertTrue(
        element("connectionMap.node.\(name)", in: app).waitForExistence(timeout: 3),
        "最短経路上の \(name) が地図に表示されていません"
      )
    }
    XCTAssertTrue(element("connectionMap.node.山田 葵", in: app).exists)
    // 詳細画面をスクロールした指がキャンバス上に掛かった場合のパンを戻し、
    // 経路全体を中央に置いた状態で比較用スクリーンショットを残す。
    let resetButton = app.buttons["connectionMap.detail.resetButton"]
    XCTAssertTrue(resetButton.waitForExistence(timeout: 3))
    resetButton.tap()
    keepScreenshot(app, name: "佐藤健太_経路強調_頭文字フォールバック_ライト")
  }

  func testDirectRenDetailCompletesIntroAtTheFocusedEndpoint() {
    let app = launch(seed: true)
    showList(in: app)
    let renCell = element("person.cell.佐藤 蓮", in: app)
    XCTAssertTrue(renCell.waitForExistence(timeout: 5))
    renCell.tap()

    app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.72))
      .press(
        forDuration: 0.05,
        thenDragTo: app.coordinate(
          withNormalizedOffset: CGVector(dx: 0.02, dy: 0.22)
        )
      )

    let canvas = element("connectionMap.canvas", in: app)
    XCTAssertTrue(canvas.waitForExistence(timeout: 5))
    for name in ["山田 太郎", "佐藤 美咲", "佐藤 修一", "佐藤 健太", "佐藤 蓮"] {
      XCTAssertTrue(element("connectionMap.node.\(name)", in: app).exists)
    }
    XCTAssertEqual(canvas.value as? String, "完了")
    keepScreenshot(app, name: "佐藤蓮_導入ズーム完了_両端後光_ライト")
    sleep(2)
  }

  func testFamilyGraphUXVisualEvidenceAcrossZoomAndLongPress() {
    let app = launch(
      seed: true,
      additionalArguments: ["-ui-testing-family-graph-ux"]
    )
    XCTAssertTrue(app.navigationBars["つながり"].waitForExistence(timeout: 5))
    let canvas = element("connectionMap.home.canvas", in: app)
    XCTAssertTrue(canvas.waitForExistence(timeout: 5))

    func waitForScale(_ expected: Double, tolerance: Double = 0.02) {
      let predicate = NSPredicate { object, _ in
        guard
          let element = object as? XCUIElement,
          let value = element.value as? String,
          let scaleText = value.components(separatedBy: "scale:").last,
          let observedScale = Double(scaleText.components(separatedBy: "|").first ?? "")
        else { return false }
        return abs(observedScale - expected) <= tolerance
      }
      let expectation = XCTNSPredicateExpectation(predicate: predicate, object: canvas)
      XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 3), .completed)
    }

    waitForScale(1)
    canvas.pinch(withScale: 0.4, velocity: -1)
    waitForScale(0.4)
    keepScreenshot(app, name: "FamilyGraphUX_01_zoom_0_4x")

    app.buttons["connectionMap.resetButton"].tap()
    waitForScale(1)
    canvas.pinch(withScale: 0.6, velocity: -1)
    waitForScale(0.6, tolerance: 0.06)
    keepScreenshot(app, name: "FamilyGraphUX_02_zoom_0_6x")

    app.buttons["connectionMap.resetButton"].tap()
    waitForScale(1)
    keepScreenshot(app, name: "FamilyGraphUX_03_zoom_1_0x")

    canvas.pinch(withScale: 2.5, velocity: 1)
    waitForScale(2.5)
    keepScreenshot(app, name: "FamilyGraphUX_04_zoom_2_5x")

    app.buttons["connectionMap.resetButton"].tap()
    waitForScale(1)
    let father = element("connectionMap.node.山田 一郎", in: app)
    XCTAssertTrue(father.waitForExistence(timeout: 5))
    XCTAssertTrue((father.value as? String)?.contains("未展開") == true)
    father.tap()
    XCTAssertTrue((father.value as? String)?.contains("focus:focused") == true)
    keepScreenshot(app, name: "FamilyGraphUX_05_focused_person")

    father.press(forDuration: 1.2)
    XCTAssertTrue(element("connectionMap.actionSheet", in: app).waitForExistence(timeout: 3))
    XCTAssertTrue((father.value as? String)?.contains("展開済み") == true)
    keepScreenshot(app, name: "FamilyGraphUX_07_long_press_action_sheet")

    app.buttons["connectionMap.menu.child"].tap()
    let nameField = element("quickRelative.name", in: app)
    XCTAssertTrue(nameField.waitForExistence(timeout: 3))
    nameField.typeText("共同の子 UX")
    app.buttons["quickRelative.save"].tap()

    let newNode = element("connectionMap.node.共同の子 UX", in: app)
    XCTAssertTrue(newNode.waitForExistence(timeout: 5))
    XCTAssertTrue(element("connectionMap.knot", in: app).waitForExistence(timeout: 3))
    let mother = element("connectionMap.node.山田 花子", in: app)
    XCTAssertTrue(mother.waitForExistence(timeout: 5))
    mother.tap()
    XCTAssertTrue(newNode.waitForExistence(timeout: 3))
    canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.55))
      .press(
        forDuration: 0.05,
        thenDragTo: canvas.coordinate(
          withNormalizedOffset: CGVector(dx: 0.45, dy: 0.55)
        )
      )
    keepScreenshot(app, name: "FamilyGraphUX_08_joint_child_after_add")

    app.buttons["connectionMap.resetButton"].tap()
    waitForScale(1)
    let spouse = element("connectionMap.node.佐藤 美咲", in: app)
    XCTAssertTrue(spouse.waitForExistence(timeout: 5))
    spouse.tap()
    let spouseFather = element("connectionMap.node.佐藤 修一", in: app)
    XCTAssertTrue(spouseFather.waitForExistence(timeout: 5))
    spouseFather.tap()
    let spouseBrother = element("connectionMap.node.佐藤 健太", in: app)
    XCTAssertTrue(spouseBrother.waitForExistence(timeout: 5))
    spouseBrother.tap()
    XCTAssertTrue(element("connectionMap.node.佐藤 蓮", in: app).waitForExistence(timeout: 5))
    canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.55))
      .press(
        forDuration: 0.05,
        thenDragTo: canvas.coordinate(
          withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)
        )
      )
    keepScreenshot(app, name: "FamilyGraphUX_06_distant_relatives")
  }

  func testFamilyConstellationSpouseFocusAndCompletedPathTransition() {
    let app = launch(
      seed: true,
      additionalArguments: ["-ui-testing-family-graph-ux"]
    )
    let canvas = element("connectionMap.home.canvas", in: app)
    XCTAssertTrue(canvas.waitForExistence(timeout: 5))

    let spouse = element("connectionMap.node.佐藤 美咲", in: app)
    XCTAssertTrue(spouse.waitForExistence(timeout: 5))
    spouse.tap()
    XCTAssertTrue((spouse.value as? String)?.contains("focus:focused") == true)
    sleep(1)
    keepScreenshot(app, name: "FamilyConstellation_03_spouse_focus")

    let spouseFather = element("connectionMap.node.佐藤 修一", in: app)
    XCTAssertTrue(spouseFather.waitForExistence(timeout: 5))
    spouseFather.tap()
    let spouseBrother = element("connectionMap.node.佐藤 健太", in: app)
    XCTAssertTrue(spouseBrother.waitForExistence(timeout: 5))
    spouseBrother.tap()
    XCTAssertTrue((spouseBrother.value as? String)?.contains("focus:focused") == true)
    sleep(1)
    keepScreenshot(app, name: "FamilyConstellation_12_focus_transition_complete")
  }

  func testFamilyConstellationVisualEvidenceWithTwentyExpandedPeople() {
    let app = launch(
      seed: true,
      additionalArguments: ["-ui-testing-family-graph-ux"]
    )
    let canvas = element("connectionMap.home.canvas", in: app)
    XCTAssertTrue(canvas.waitForExistence(timeout: 5))
    let father = element("connectionMap.node.山田 一郎", in: app)
    XCTAssertTrue(father.waitForExistence(timeout: 5))
    father.tap()

    func addJointChild(number: Int) {
      father.press(forDuration: 0.7)
      let childAction = app.buttons["connectionMap.menu.child"]
      XCTAssertTrue(childAction.waitForExistence(timeout: 3))
      childAction.tap()
      let field = element("quickRelative.name", in: app)
      XCTAssertTrue(field.waitForExistence(timeout: 3))
      let name = "共同の子 \(number)"
      field.typeText(name)
      app.buttons["quickRelative.save"].tap()
      XCTAssertTrue(
        element("connectionMap.node.\(name)", in: app).waitForExistence(timeout: 5)
      )
    }

    for number in 1...12 {
      addJointChild(number: number)
    }

    let spouse = element("connectionMap.node.佐藤 美咲", in: app)
    XCTAssertTrue(spouse.waitForExistence(timeout: 5))
    spouse.tap()
    let spouseFather = element("connectionMap.node.佐藤 修一", in: app)
    XCTAssertTrue(spouseFather.waitForExistence(timeout: 5))
    spouseFather.tap()
    let spouseBrother = element("connectionMap.node.佐藤 健太", in: app)
    XCTAssertTrue(spouseBrother.waitForExistence(timeout: 5))

    app.buttons["connectionMap.resetButton"].tap()
    canvas.pinch(withScale: 0.4, velocity: -1)
    XCTAssertTrue((canvas.value as? String)?.contains("nodes:20") == true)
    sleep(1)
    keepScreenshot(app, name: "FamilyConstellation_08_twenty_people")
  }

  func testMapContextMenuDetailNavigationAndAvailableParentAction() {
    let app = launch(seed: true)
    XCTAssertTrue(app.navigationBars["つながり"].waitForExistence(timeout: 5))

    let father = element("connectionMap.node.山田 一郎", in: app)
    XCTAssertTrue(father.waitForExistence(timeout: 5))
    father.press(forDuration: 1.2)
    XCTAssertTrue(app.buttons["詳細を見る"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.buttons["親を追加"].exists)
    XCTAssertTrue(app.buttons["子を追加"].exists)
    XCTAssertFalse(app.buttons["配偶者を追加"].exists)
    app.buttons["詳細を見る"].tap()

    XCTAssertTrue(app.navigationBars["山田 一郎"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["編集"].exists)
  }

  func testRelationEditorButtonIsVisibleDirectlyBelowProfileHeader() {
    let app = launch(seed: true)
    showList(in: app)
    let selfCell = element("person.cell.山田 太郎", in: app)
    XCTAssertTrue(selfCell.waitForExistence(timeout: 5))
    selfCell.tap()

    let relationButton = app.buttons["personDetail.editRelations"]
    XCTAssertTrue(relationButton.waitForExistence(timeout: 5))
    XCTAssertTrue(relationButton.isHittable)
    XCTAssertLessThan(relationButton.frame.maxY, app.frame.midY + 120)

    relationButton.tap()
    XCTAssertTrue(app.navigationBars["山田 太郎さんの関係"].waitForExistence(timeout: 5))
  }

  func testPersonDetailSectionsTopToBottomScreenshots() {
    let app = launch(seed: true)
    showList(in: app)
    let selfCell = element("person.cell.山田 太郎", in: app)
    XCTAssertTrue(selfCell.waitForExistence(timeout: 5))
    selfCell.tap()

    let relationButton = app.buttons["personDetail.editRelations"]
    XCTAssertTrue(relationButton.waitForExistence(timeout: 5))
    XCTAssertTrue(relationButton.isHittable)
    keepScreenshot(app, name: "人物詳細_01_見出しと関係編集_ライト")

    let scrollStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.76))
    let scrollEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.28))
    scrollStart.press(forDuration: 0.05, thenDragTo: scrollEnd)
    XCTAssertTrue(element("connectionMap.node.山田 太郎", in: app).waitForExistence(timeout: 5))
    let gathering = app.staticTexts["祖母の一周忌"]
    XCTAssertTrue(gathering.waitForExistence(timeout: 5))
    keepScreenshot(app, name: "人物詳細_02_プロフィール・つながり・集まり_ライト")
  }

  func testExpiredTrialBlocksEditingButKeepsExistingDataReadable() {
    var app = launch(
      seed: true,
      additionalArguments: ["-ui-testing-trial-expired"]
    )
    showList(in: app)
    let kentaCell = element("person.cell.佐藤 健太", in: app)
    XCTAssertTrue(kentaCell.waitForExistence(timeout: 5))

    // 期限切れ後も既存データの詳細閲覧と地図は開ける。
    kentaCell.tap()
    XCTAssertTrue(app.navigationBars["佐藤 健太"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["編集"].exists)
    app.buttons["編集"].tap()

    XCTAssertTrue(element("purchase.sheet", in: app).waitForExistence(timeout: 5))
    let buyButton = app.buttons["purchase.buyButton"]
    XCTAssertTrue(buyButton.exists)
    XCTAssertTrue(app.buttons["purchase.retryProductButton"].waitForExistence(timeout: 5))
    XCTAssertTrue(buyButton.label.contains("商品情報を読み込んで購入"))
    XCTAssertTrue(app.buttons["purchase.restoreButton"].exists)
    XCTAssertTrue(element("purchase.message", in: app).exists)
    keepScreenshot(app, name: "試用期間終了_購入シート_ライト")
    app.buttons["閉じる"].tap()

    app.navigationBars.buttons.element(boundBy: 0).tap()
    app.buttons["人物を追加"].tap()
    XCTAssertTrue(element("purchase.sheet", in: app).waitForExistence(timeout: 5))
    XCTAssertFalse(element("personForm.name", in: app).exists)
    app.buttons["閉じる"].tap()

    app.buttons["設定"].tap()
    let trialStatus = element("settings.trialStatus", in: app)
    XCTAssertTrue(trialStatus.waitForExistence(timeout: 5))
    XCTAssertTrue(trialStatus.label.contains("試用期間は終了しました"))

    // StoreKit購入結果と同じ purchased 状態なら、即座に編集ロックが外れる。
    app.terminate()
    app = launch(
      reset: false,
      additionalArguments: ["-ui-testing-purchased"]
    )
    XCTAssertTrue(app.buttons["親戚"].waitForExistence(timeout: 5))
    app.buttons["設定"].tap()
    let purchasedStatus = element("settings.trialStatus", in: app)
    XCTAssertTrue(purchasedStatus.waitForExistence(timeout: 5))
    XCTAssertTrue(purchasedStatus.label.contains("購入済み"))
    app.buttons["親戚"].tap()
    app.buttons["人物を追加"].tap()
    XCTAssertTrue(element("personForm.name", in: app).waitForExistence(timeout: 5))
    XCTAssertFalse(element("purchase.sheet", in: app).exists)
  }
}
