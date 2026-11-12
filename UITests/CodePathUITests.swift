import XCTest

@MainActor
final class CodePathUITests: XCTestCase {
    func testLearningAndRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let data = project.appendingPathComponent(".build/xcui-data/\(UUID().uuidString)")
        app.launchEnvironment["CODEPATH_DATA_DIR"] = data.path
        app.launch()
        XCTAssertTrue(app.buttons["Продолжить обучение"].waitForExistence(timeout: 10))
        attach(app, "Главная")
        app.buttons["Продолжить обучение"].click()
        XCTAssertTrue(app.staticTexts["Маяк станции"].waitForExistence(timeout: 5))
        // Hide theory to make the editable area visible without a large scroll.
        app.buttons["Скрыть теорию"].click()
        let editor = app.textViews.matching(NSPredicate(format: "label BEGINSWITH %@", "Редактор C++")).firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.click()
        editor.typeKey("a", modifierFlags: .command)
        editor.typeText("// saved draft")
        let completion = app.buttons["Я проверил(а) решение — отметить выполненным"]
        if !completion.isHittable { app.scrollViews.allElementsBoundByIndex.last?.swipeUp() }
        completion.click()
        XCTAssertTrue(app.staticTexts["Отмечено вами"].waitForExistence(timeout: 5))
        attach(app, "Черновик и самостоятельная отметка")
        app.terminate()
        app.launch()
        app.buttons["Продолжить обучение"].click()
        app.buttons["Скрыть теорию"].click()
        let restored = app.textViews.matching(NSPredicate(format: "label BEGINSWITH %@", "Редактор C++")).firstMatch
        XCTAssertTrue(restored.waitForExistence(timeout: 5))
        XCTAssertEqual(restored.value as? String, "// saved draft")
        XCTAssertTrue(app.staticTexts["Отмечено вами"].exists)
        attach(app, "Восстановление после перезапуска")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
