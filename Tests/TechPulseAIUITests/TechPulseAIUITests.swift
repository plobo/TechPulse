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
        XCTAssertTrue(app.otherElements["aiReader.unavailable"].waitForExistence(timeout: 5)
                      || app.staticTexts["AI isn’t available on this device"].waitForExistence(timeout: 2))
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

    // MARK: - Milestone 4 (Demo AI)

    private func openFirstArticle(_ app: XCUIApplication) {
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'article.card.'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        XCTAssertTrue(app.buttons["detail.openOriginal"].waitForExistence(timeout: 5))
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func scrollTo(_ el: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 where !(el.exists && el.isHittable) { app.swipeUp() }
    }

    func testSummaryLengthSwitchShowsLabels() {
        let app = launch(["-demo-ai"])
        openFirstArticle(app)
        let detailed = app.buttons["Detailed"]
        scrollTo(detailed, in: app)
        XCTAssertTrue(detailed.waitForExistence(timeout: 5))
        detailed.tap()
        let generate = element(app, "ai.summary.generate")
        XCTAssertTrue(generate.waitForExistence(timeout: 5))
        generate.tap()
        let text = element(app, "ai.summary.text")
        XCTAssertTrue(text.waitForExistence(timeout: 10))
        XCTAssertTrue(text.label.contains("Demo AI"))
        XCTAssertTrue(element(app, "ai.label.demo").exists)
        XCTAssertTrue(element(app, "ai.label.basis").exists)
    }

    func testAskArticleFlow() {
        let app = launch(["-demo-ai"])
        openFirstArticle(app)
        let ask = app.buttons["ai.ask"]
        scrollTo(ask, in: app)
        ask.tap()
        let field = element(app, "ai.ask.field")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("What is this about?")
        app.buttons["ai.ask.send"].tap()
        let answer = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'canned answer'")).firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 10))
    }

    func testDiagramRendersWithTextAlternative() {
        let app = launch(["-demo-ai"])
        openFirstArticle(app)
        let diagram = app.buttons["ai.diagram"]
        scrollTo(diagram, in: app)
        diagram.tap()
        let generate = element(app, "ai.diagram.generate")
        XCTAssertTrue(generate.waitForExistence(timeout: 5))
        generate.tap()
        XCTAssertTrue(element(app, "ai.diagram.text").waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, "ai.diagram.copy").exists)
    }

    func testAIReaderListsSavedItemsAfterRelaunch() {
        var app = launch(["-demo-ai", "-persistent-store", "-reset-store"])
        openFirstArticle(app)
        let generate = element(app, "ai.summary.generate")
        scrollTo(generate, in: app)
        generate.tap()
        XCTAssertTrue(element(app, "ai.summary.text").waitForExistence(timeout: 10))
        app.terminate()

        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-demo-ai", "-persistent-store"]
        app.launch()
        app.tabBars.buttons["AI Reader"].tap()
        let list = element(app, "aiReader.list")
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        XCTAssertTrue(app.cells.containing(NSPredicate(format: "label CONTAINS 'Summary'")).firstMatch.waitForExistence(timeout: 5)
                      || app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Summary'")).firstMatch.exists)
    }
}
