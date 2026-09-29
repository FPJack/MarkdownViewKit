import XCTest
import UIKit
import SwiftMarkdownViewKit

class Tests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testExample() {
        // This is an example of a functional test case.
        XCTAssert(true, "Pass")
    }

    func testCodeBlockTrailingNewlineDoesNotAddRow() {
        func height(_ code: String) -> CGFloat {
            let text = NSAttributedString(string: code, attributes: [.font: UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)])
            return CodeBlockView.calculateSize(attributedText: text, maxViewWidth: 320).height
        }

        let code = "import UIKit\n\nfunc render(markdown: String) {\n    markdownView.render(markdown)\n}"
        XCTAssertEqual(height(code), height(code + "\n"))
        XCTAssertEqual(height(code), height(code.replacingOccurrences(of: "\n", with: "\r\n") + "\r\n"))
        XCTAssertGreaterThan(height(code + "\n\n"), height(code + "\n"))
    }
    
    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure() {
            // Put the code you want to measure the time of here.
        }
    }
    
}
