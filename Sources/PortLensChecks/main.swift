import Foundation
import Darwin
import PortLensValidation

let results = CoreValidation.runAll()
for result in results {
    if let failure = result.failure {
        print("FAIL  \(result.name)\n      \(failure)")
    } else {
        print("PASS  \(result.name)")
    }
}
let failures = results.filter { !$0.passed }.count
print("\n\(results.count - failures)/\(results.count) validation cases passed.")
exit(failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE)
