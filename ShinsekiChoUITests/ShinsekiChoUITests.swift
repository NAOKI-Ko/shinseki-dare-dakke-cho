import XCTest

final class ShinsekiChoUITests: XCTestCase {
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func launch(reset: Bool = true, seed: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments: [String] = []
        arguments.append(contentsOf: ["-ui-testing", "-AppleInterfaceStyle", "Light"])
        if reset { arguments.append("-ui-testing-reset") }
        if seed { arguments.append("-ui-testing-seed") }
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
               element.frame.maxY <= visibleBottom {
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

    func testSeededGraphExpansionGesturesResetGatheringPhotoAndPersistence() {
        var app = launch(seed: true)
        XCTAssertTrue(app.buttons["親戚"].waitForExistence(timeout: 5))
        let selfCell = element("person.cell.山田 太郎", in: app)
        XCTAssertTrue(selfCell.waitForExistence(timeout: 5))
        XCTAssertEqual(selfCell.value as? String, "写真なし")
        XCTAssertEqual(
            element("person.cell.佐藤 美咲", in: app).value as? String,
            "写真あり"
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
        XCTAssertTrue(element("connectionMap.node.山田 太郎", in: app).exists)
        XCTAssertTrue(element("connectionMap.node.山田 一郎", in: app).exists)
        XCTAssertTrue(element("connectionMap.node.山田 花子", in: app).exists)
        XCTAssertTrue(element("connectionMap.node.佐藤 美咲", in: app).exists)
        XCTAssertTrue(element("connectionMap.node.山田 葵", in: app).exists)
        XCTAssertFalse(element("connectionMap.node.山田 次郎", in: app).exists)
        let legend = element("connectionMap.legend", in: app)
        XCTAssertTrue(legend.exists)
        XCTAssertTrue(legend.label.contains("直系"))
        XCTAssertTrue(legend.label.contains("配偶者側"))
        XCTAssertTrue(legend.label.contains("外側の家系"))
        let selfNode = element("connectionMap.node.山田 太郎", in: app)
        XCTAssertEqual(selfNode.frame.midX, app.frame.midX, accuracy: 2)

        let beforeExpansion = XCTAttachment(screenshot: app.screenshot())
        beforeExpansion.name = "つながりマップ_展開前_5ノード_ライト"
        beforeExpansion.lifetime = .keepAlways
        add(beforeExpansion)

        let father = element("connectionMap.node.山田 一郎", in: app)
        XCTAssertEqual(father.value as? String, "未展開")
        let appFrame = app.frame
        let mapTop = app.staticTexts["つながり"].frame.maxY
        app.coordinate(
            withNormalizedOffset: CGVector(
                dx: father.frame.midX / appFrame.width,
                dy: (mapTop + 130.0) / appFrame.height
            )
        ).tap()
        XCTAssertTrue(element("connectionMap.node.山田 次郎", in: app).waitForExistence(timeout: 3))
        XCTAssertEqual(father.value as? String, "展開済み")
        let initialSelfFrame = selfNode.frame
        canvas.pinch(withScale: 1.4, velocity: 1)
        canvas.swipeLeft()
        XCTAssertGreaterThan(abs(selfNode.frame.midX - initialSelfFrame.midX), 10)
        app.buttons["connectionMap.resetButton"].tap()
        XCTAssertEqual(selfNode.frame.midX, initialSelfFrame.midX, accuracy: 2)
        XCTAssertEqual(selfNode.frame.midY, initialSelfFrame.midY, accuracy: 2)

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
        XCTAssertTrue(element("person.cell.山田 太郎", in: app).waitForExistence(timeout: 5))
        app.buttons["集まり"].tap()
        XCTAssertTrue(app.staticTexts["祖母の一周忌"].waitForExistence(timeout: 5))
        app.buttons["親戚"].tap()
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
}
