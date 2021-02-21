import XCTest
@testable import FireKit

final class FireKitTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertEqual(FireKit().text, "Hello, World!")
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
