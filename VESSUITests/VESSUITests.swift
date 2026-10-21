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
        XCTAssertEqual(dayWord.label, "Nothing logged yet today.")
        XCTAssertTrue(app.descendants(matching: .any)["today.fuel"].exists, "The Fuel ring shows \u{2014} before the first log")
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
        let addDinner = app.buttons["nutrition.add.dinner"]
        scrollUntilHittable(addDinner, in: app)
        addDinner.tap()
        tapWhenReady(app.buttons["foodSearch.quickAdd"])

        let submit = app.buttons["addFood.submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 10))
        XCTAssertFalse(submit.isEnabled, "A name and calories are required")

        type("Lentil soup", into: app.textFields["Food"])
        type("320", into: app.textFields["Calories"])

        // Asserts the button is enabled once the keyboard is closed, then submits.
        submitAndConfirmDismissal(submit, in: app)

        // The diary row combines name and detail for VoiceOver ("Lentil soup, Quick add …").
        let entry = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Lentil soup")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 10), "The new entry appears in the diary")
    }

    @MainActor
    func testSearchLogEditAndDeleteCatalogFood() throws {
        let app = launch(seeded: true)

        app.tabBars.buttons["Nutrition"].tap()
        let addDinner = app.buttons["nutrition.add.dinner"]
        scrollUntilHittable(addDinner, in: app)
        addDinner.tap()

        // Local results appear without the network; UI tests run offline,
        // so the online section must say so instead of failing silently.
        type("Lentils", into: app.textFields["foodSearch.query"])
        let onlineMessage = app.staticTexts["foodSearch.onlineMessage"]
        XCTAssertTrue(onlineMessage.waitForExistence(timeout: 10))
        XCTAssertTrue(onlineMessage.label.contains("offline"), "Offline is explained: \(onlineMessage.label)")

        tapWhenReady(app.buttons["foodRow.Lentils, cooked"])
        let add = app.buttons["foodDetail.add"]
        waitFor(add, "isHittable == true")
        XCTAssertTrue(app.staticTexts["Typical values from USDA FoodData Central"].exists)
        add.tap()
        waitFor(add, "exists == false")

        // Logged with the default portion, "1 cup".
        let entry = app.buttons["entry.Lentils, cooked"]
        scrollUntilHittable(entry, in: app)
        XCTAssertTrue(entry.label.contains("1 cup"), "Entry shows its portion: \(entry.label)")

        // Edit: two portions.
        entry.tap()
        type("2", into: app.textFields["Portions"])
        submitAndConfirmDismissal(app.buttons["editEntry.save"], in: app)
        scrollUntilHittable(entry, in: app)
        XCTAssertTrue(entry.label.contains("2 × 1 cup"), "Entry shows the new amount: \(entry.label)")

        // Delete.
        entry.tap()
        tapWhenReady(app.buttons["editEntry.delete"])
        waitFor(entry, "exists == false")
    }

    // MARK: Navigation

    @MainActor
    func testAllFourTabsOpen() throws {
        let app = launch(seeded: true)
        let tabs = app.tabBars

        XCTAssertTrue(app.staticTexts["today.dayWord"].waitForExistence(timeout: 5))
        XCTAssertFalse(tabs.buttons["Activity"].exists, "Activity is a detail screen, not a tab")
        XCTAssertFalse(tabs.buttons["Profile"].exists, "Profile is now called You")

        tabs.buttons["Nutrition"].tap()
        XCTAssertTrue(app.navigationBars["Nutrition"].waitForExistence(timeout: 10))

        tabs.buttons["Plan"].tap()
        XCTAssertTrue(app.navigationBars["Plan"].waitForExistence(timeout: 10))

        tabs.buttons["You"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["you.header"].waitForExistence(timeout: 10))

        tabs.buttons["Today"].tap()
        XCTAssertTrue(app.staticTexts["today.dayWord"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testAddOpensSheetAndKeepsTab() throws {
        let app = launch(seeded: true)
        let tabs = app.tabBars

        tapWhenReady(tabs.buttons["Nutrition"])
        XCTAssertTrue(app.navigationBars["Nutrition"].waitForExistence(timeout: 10))

        tapWhenReady(tabs.buttons["Add"])
        let quickAdd = app.buttons["foodSearch.quickAdd"]
        XCTAssertTrue(quickAdd.waitForExistence(timeout: 10), "Add opens the Add sheet")
        XCTAssertTrue(app.buttons["foodSearch.barcode"].exists)

        app.buttons["Close"].firstMatch.tap()
        waitFor(quickAdd, "exists == false")
        XCTAssertTrue(app.navigationBars["Nutrition"].waitForExistence(timeout: 10), "The tab stays where it was")
    }

    @MainActor
    func testActivityOpensFromToday() throws {
        let app = launch(seeded: true)
        let activity = app.buttons["today.activity"]
        scrollUntilHittable(activity, in: app)
        activity.tap()
        XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: 10))
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

    /// Scrolls the screen until `element` can be tapped (diary rows can sit
    /// below the fold on a full day).
    @MainActor
    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "Missing \(element)")
        for _ in 0..<6 where !element.isHittable {
            app.swipeUp()
        }
        waitFor(element, "isHittable == true")
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
        // Keystrokes reach the field's value asynchronously, so wait for the
        // value by predicate before deciding a retry is needed.
        let typed = NSPredicate(format: "value == %@", text)
        for _ in 0..<2 {
            clear(field)
            field.typeText(text)
            if wait(for: field, typed, timeout: 10) { break }
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
    /// button to become tappable (screens hide it while the keyboard is up),
    /// asserts it is enabled, submits, and asserts the screen closed.
    @MainActor
    private func submitAndConfirmDismissal(_ submit: XCUIElement, in app: XCUIApplication) {
        let done = app.buttons["keyboard.done"]
        if done.exists {
            done.tap()
            waitFor(done, "exists == false")
        }
        waitFor(submit, "isHittable == true")
        XCTAssertTrue(submit.isEnabled, "\(submit) is enabled once the form is complete")
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
        wait(for: element, NSPredicate(format: predicate), timeout: timeout)
    }

    @MainActor
    private func wait(for element: XCUIElement, _ predicate: NSPredicate, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
