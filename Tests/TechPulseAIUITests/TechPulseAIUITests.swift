import XCTest

@MainActor
final class TechPulseAIUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + extra
        app.launch()
        return app
    }

    func testNavigatesAcrossAllFiveTabs() {
        let app = launch()
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 10))
        for (tab, title) in [("Explore", "Explore"), ("AI Reader", "AI Reader"), ("Library", "Library"),
                             ("Profile", "Profile"), ("Discover", "Discover")] {
            tabs.buttons[tab].tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5), "missing \(title)")
        }
    }

    func testDiscoverShowsSampleFeedAndOpensArticleWithSourceLink() {
        let app = launch()
        XCTAssertTrue(app.otherElements["sample.banner"].waitForExistence(timeout: 10) || app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'sample data'")).firstMatch.exists)
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'article.card.'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        XCTAssertTrue(app.buttons["detail.openOriginal"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["detail.bookmark"].exists)
    }

    func testCategoryChipFiltersFeed() {
        let app = launch()
        let chip = app.buttons["chip.ai-ml"]
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        chip.tap()
        XCTAssertTrue(chip.isSelected, "selection exposed to accessibility")
        XCTAssertTrue(app.staticTexts["AI & Machine Learning"].waitForExistence(timeout: 5))
    }

    func testSearchFindsSampleArticles() {
        let app = launch()
        app.tabBars.buttons["Explore"].tap()
        app.buttons["explore.search"].firstMatch.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("swift")
        let result = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'article.card.'")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5))
    }

    func testAIReaderShowsUnavailableState() {
        let app = launch()
        app.tabBars.buttons["AI Reader"].tap()
        XCTAssertTrue(app.staticTexts["AI Reader is coming soon"].waitForExistence(timeout: 5))
    }

    func testBookmarkPersistsAfterRelaunch() {
        var app = launch(["-persistent-store", "-reset-store"])
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'article.card.'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        let bookmark = app.buttons["detail.bookmark"]
        XCTAssertTrue(bookmark.waitForExistence(timeout: 5))
        bookmark.tap()
        XCTAssertTrue(app.buttons["Remove Bookmark"].waitForExistence(timeout: 5))
        app.terminate()

        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-persistent-store"]
        app.launch()
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["library.empty"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.cells.firstMatch.waitForExistence(timeout: 5) || app.buttons.matching(NSPredicate(format: "label CONTAINS 'Sample'")).firstMatch.exists)
    }

    func testDiscoverSupportsLargestDynamicType() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Discover"].waitForExistence(timeout: 10))
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'article.card.'")).firstMatch
        for _ in 0..<8 where !card.exists { app.swipeUp() }
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertFalse(card.label.isEmpty, "cards must expose a VoiceOver label")
    }
}
