import Foundation

extension URL {
    /// A URL from a compile-time-constant string literal, for `static let` endpoints (S-ERR-1).
    /// A malformed literal is a programmer error that no user data can reach (S-ERR-5), so it
    /// traps with the literal named — on the first test run that touches the constant.
    init(checkedLiteral literal: StaticString) {
        guard let url = URL(string: "\(literal)") else {
            preconditionFailure("Malformed URL literal: \(literal)")
        }
        self = url
    }
}
