import XCTest

/// End-to-end flows. Every test launches with `-uiTesting`, which gives the
/// app an empty in-memory store, so tests never touch real data and never
/// depend on each other. `-seedSampleData` adds the Debug-only sample day.
final class VESSUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(seeded: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + (seeded ? ["-seedSampleData"] : [])
        app.launch()
        return app
    }

    // MARK: Onboarding

    @MainActor
    func testOnboardingCreatesProfileAndOpensToday() throws {
        let app = launch(seeded: false)

        tapWhenReady(app.buttons["onboarding.getStarted"])

        let continueButton = app.buttons["onboarding.continue"]
        tapWhenReady(app.buttons["Build muscle"], disabledCheck: continueButton)
        continueButton.tap()

        // Basics
        XCTAssertTrue(app.staticTexts["A little about you"].waitForExistence(timeout: 10))
        XCTAssertFalse(continueButton.isEnabled)
        type("Mark", into: app.textFields["What should we call you?"])
        type("29", into: app.textFields["Age"])
        tapWhenReady(app.buttons["Male"])
        type("178", into: app.textFields["Height"])
        type("68", into: app.textFields["Weight"])
        dismissKeyboard(in: app)
        XCTAssertTrue(continueButton.isEnabled)
        continueButton.tap()

        // Option rows read title and detail together, for example
        // "Moderate, Exercise 3–5 days a week".
        tapWhenReady(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Moderate")).firstMatch)
        continueButton.tap()

        tapWhenReady(app.buttons["Everything"])
        continueButton.tap()

        // Restrictions and focus areas are optional.
        XCTAssertTrue(app.staticTexts["Anything you avoid?"].waitForExistence(timeout: 10))
        XCTAssertTrue(continueButton.isEnabled)
        continueButton.tap()
        XCTAssertTrue(app.staticTexts["What matters to you?"].waitForExistence(timeout: 10))
        continueButton.tap()

        // Apple Health: choosing "Not now" finishes without any permission prompt.
        tapWhenReady(app.buttons["onboarding.notNow"])

        let dayWord = app.staticTexts["today.dayWord"]
        XCTAssertTrue(dayWord.waitForExistence(timeout: 5))
        XCTAssertEqual(dayWord.label, "Fresh start")
        XCTAssertTrue(app.staticTexts["Good morning, Mark"].exists
            || app.staticTexts["Good afternoon, Mark"].exists
            || app.staticTexts["Good evening, Mark"].exists)
    }

    // MARK: Water

    @MainActor
    func testQuickAddWaterThenUndo() throws {
        let app = launch(seeded: true)

        let water = app.descendants(matching: .any)["today.water.value"]
        XCTAssertTrue(water.waitForExistence(timeout: 5))
        let before = try XCTUnwrap(water.value as? String)

        app.buttons["today.water.add250"].tap()

        // The Undo toast is shown for 4 seconds, so find it first; reading
        // values takes accessibility snapshots that can eat into that window.
        let undo = app.buttons["undoToast.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 4))

        let afterAdding = try XCTUnwrap(water.value as? String)
        XCTAssertNotEqual(afterAdding, before, "Adding 250 ml updates the water total immediately")

        undo.tap()
        XCTAssertEqual(water.value as? String, before, "Undo removes the log")
    }

    // MARK: Food

    @MainActor
    func testQuickAddFoodAppearsInDiary() throws {
        let app = launch(seeded: true)

        app.tabBars.buttons["Nutrition"].tap()
        app.buttons["nutrition.addFood"].tap()

        let submit = app.buttons["addFood.submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 10))
        XCTAssertFalse(submit.isEnabled, "A name and calories are required")

        type("Lentil soup", into: app.textFields["Food"])
        type("320", into: app.textFields["Calories"])
        XCTAssertTrue(submit.isEnabled)

        submitAndConfirmDismissal(submit, in: app)

        // The diary row combines name and detail for VoiceOver ("Lentil soup, Quick add …").
        let entry = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Lentil soup")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 10), "The new entry appears in the diary")
    }

    // MARK: Navigation

    @MainActor
    func testAllFiveTabsOpen() throws {
        let app = launch(seeded: true)
        let tabs = app.tabBars

        XCTAssertTrue(app.staticTexts["today.dayWord"].waitForExistence(timeout: 5))

        tabs.buttons["Nutrition"].tap()
        XCTAssertTrue(app.navigationBars["Nutrition"].waitForExistence(timeout: 10))

        tabs.buttons["Plan"].tap()
        XCTAssertTrue(app.navigationBars["Plan"].waitForExistence(timeout: 10))

        tabs.buttons["Activity"].tap()
        XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: 10))

        tabs.buttons["Profile"].tap()
        XCTAssertTrue(app.staticTexts["Daily targets"].waitForExistence(timeout: 10))

        tabs.buttons["Today"].tap()
        XCTAssertTrue(app.staticTexts["today.dayWord"].exists)
    }

    // MARK: Helpers

    /// Waits for an element to appear and become tappable, closing the
    /// keyboard first if it covers the element, then taps it. If
    /// `disabledCheck` is given, asserts that button is disabled before the tap.
    @MainActor
    private func tapWhenReady(_ element: XCUIElement, disabledCheck: XCUIElement? = nil) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "Missing \(element)")
        if !element.isHittable { dismissKeyboard(in: XCUIApplication()) }
        let hittable = expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: element)
        wait(for: [hittable], timeout: 10)
        if let disabledCheck {
            XCTAssertFalse(disabledCheck.isEnabled, "\(disabledCheck) should be disabled until a choice is made")
        }
        element.tap()
    }

    /// Closes the software keyboard with its Done button, if it is showing.
    @MainActor
    private func dismissKeyboard(in app: XCUIApplication) {
        let done = app.buttons["keyboard.done"]
        if done.exists && done.isHittable { done.tap() }
    }

    /// Replaces a field's contents with `text` and verifies the result.
    ///
    /// Deterministic by construction: waits until the field can be tapped,
    /// confirms focus by predicate (not a fixed sleep), clears anything already
    /// in the field, then asserts the field holds exactly `text`. A dropped or
    /// duplicated keystroke fails here, at its source.
    @MainActor
    private func type(_ text: String, into field: XCUIElement) {
        XCTAssertTrue(field.waitForExistence(timeout: 10), "Missing field \(field)")
        // With the software keyboard shown, a lower field can sit under it.
        // Close the keyboard with its Done button, as a person would.
        if !field.isHittable {
            dismissKeyboard(in: XCUIApplication())
        }
        waitFor(field, "isHittable == true")

        // A tap during a sheet's presentation can be dropped: tap, wait for
        // focus, and tap once more only if focus didn't arrive.
        field.tap()
        if !wait(for: field, "hasKeyboardFocus == true", timeout: 3) {
            field.tap()
        }
        waitFor(field, "hasKeyboardFocus == true")

        // Clear, type, and verify. On a heavily loaded Simulator the software
        // keyboard can drop keystrokes, so one clean retry is allowed; the
        // field must still end up holding exactly `text`.
        for _ in 0..<2 {
            clear(field)
            field.typeText(text)
            if field.value as? String == text { break }
        }
        XCTAssertEqual(field.value as? String, text, "Field holds exactly what was typed")
    }

    /// Deletes any text in a focused field (placeholder text is not content).
    @MainActor
    private func clear(_ field: XCUIElement) {
        guard let current = field.value as? String, !current.isEmpty, current != field.placeholderValue else { return }
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
    }

    /// Closes the keyboard through its Done button, waits for the submit
    /// button to become tappable, submits, and asserts the sheet closed.
    @MainActor
    private func submitAndConfirmDismissal(_ submit: XCUIElement, in app: XCUIApplication) {
        let done = app.buttons["keyboard.done"]
        if done.exists {
            done.tap()
            waitFor(done, "exists == false")
        }
        waitFor(submit, "isHittable == true")
        submit.tap()
        waitFor(submit, "exists == false")
    }

    /// Waits for `predicate` on `element`, failing the test if it never holds.
    @MainActor
    private func waitFor(_ element: XCUIElement, _ predicate: String, timeout: TimeInterval = 10) {
        XCTAssertTrue(wait(for: element, predicate, timeout: timeout), "Timed out waiting for \(predicate) on \(element)")
    }

    /// Waits for `predicate` on `element`; returns whether it held in time.
    @MainActor
    private func wait(for element: XCUIElement, _ predicate: String, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
