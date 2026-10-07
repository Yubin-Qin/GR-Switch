import XCTest
@testable import GRCore

final class CoreTests: XCTestCase {
    func testCoreScenarios() throws {
        for (name, test) in CoreScenarios.tests {
            do { try test() } catch { XCTFail("\(name): \(error)") }
        }
    }
}
