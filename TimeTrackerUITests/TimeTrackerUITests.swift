import XCTest

final class TimeTrackerUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
    }

    @MainActor
    func testTimelineShowsSlots() throws {
        let firstSlot = findSlot("7:30 AM - 8:00 AM")
        XCTAssertTrue(firstSlot.exists, "First slot should be visible")
    }

    @MainActor
    func testTapSlotNavigatesToEdit() throws {
        let firstSlot = findSlot("7:30 AM - 8:00 AM")
        XCTAssertTrue(firstSlot.exists)
        firstSlot.tap()

        let logEntryTitle = app.navigationBars["Log Entry"]
        XCTAssertTrue(logEntryTitle.waitForExistence(timeout: 3), "Should navigate to Log Entry view")
    }

    @MainActor
    func testSubmitEntry() throws {
        // Navigate to a slot that won't have prior data (use a later slot)
        let slot = findSlot("8:00 AM - 8:30 AM")
        XCTAssertTrue(slot.exists)
        slot.tap()

        let field = app.textFields["entryTextField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Text field should exist")
        field.tap()
        field.typeText("Test entry from UI test")

        let submitButton = app.buttons["Submit"]
        XCTAssertTrue(submitButton.waitForExistence(timeout: 3))
        submitButton.tap()

        XCTAssertTrue(findSlot("8:00 AM - 8:30 AM").exists)
        let entryText = app.staticTexts["Test entry from UI test"]
        XCTAssertTrue(entryText.waitForExistence(timeout: 5), "Submitted entry should appear in timeline")
    }

    @MainActor
    func testEditShowsUpdateButton() throws {
        // First submit
        let slot = findSlot("8:30 AM - 9:00 AM")
        XCTAssertTrue(slot.exists)
        slot.tap()

        let field = app.textFields["entryTextField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Entry to edit")

        app.buttons["Submit"].tap()

        // Tap same slot again
        let filledSlot = app.staticTexts["8:30 AM - 9:00 AM"]
        XCTAssertTrue(filledSlot.waitForExistence(timeout: 5))
        filledSlot.tap()

        let updateButton = app.buttons["Update"]
        XCTAssertTrue(updateButton.waitForExistence(timeout: 5), "Should show Update button for existing entry")
    }

    @MainActor
    func testDateNavigationButtons() throws {
        let chevronLeft = app.buttons["chevron.left"]
        let chevronRight = app.buttons["chevron.right"]
        XCTAssertTrue(chevronLeft.waitForExistence(timeout: 5), "Left arrow should exist")
        XCTAssertTrue(chevronRight.exists, "Right arrow should exist")
    }

    @MainActor
    func testBackNavigationFromEdit() throws {
        let firstSlot = findSlot("7:30 AM - 8:00 AM")
        XCTAssertTrue(firstSlot.exists)
        firstSlot.tap()

        let backButton = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(backButton.waitForExistence(timeout: 3))
        backButton.tap()

        XCTAssertTrue(findSlot("7:30 AM - 8:00 AM").exists, "Should be back on timeline")
    }

    private func findSlot(_ label: String) -> XCUIElement {
        let slot = app.staticTexts[label]
        if slot.waitForExistence(timeout: 2), slot.isHittable {
            return slot
        }

        for _ in 0..<8 {
            app.swipeDown()
            if slot.waitForExistence(timeout: 0.5), slot.isHittable {
                return slot
            }
        }

        return slot
    }
}
