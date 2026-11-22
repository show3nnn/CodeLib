#if DEBUG
import Testing
@testable import CodePathApp

struct AcceptanceValidationTests {
    @Test func missingScreenshotAndExitCode() {
        let required: Set<String> = ["home", "lesson"]
        #expect(AcceptanceValidation.missingCaptures(required: required, recorded: required, existingFiles: required).isEmpty)
        #expect(AcceptanceValidation.missingCaptures(required: required, recorded: ["home"], existingFiles: required) == ["lesson"])
        #expect(AcceptanceValidation.missingCaptures(required: required, recorded: required, existingFiles: ["home"]) == ["lesson"])
        #expect(AcceptanceValidation.exitCode(failures: []) == 0)
        #expect(AcceptanceValidation.exitCode(failures: ["missing"]) != 0)
    }

    @Test func emptyAndTruncatedAccessibilityTreesFail() {
        #expect(AcceptanceValidation.axFailure(nodeCount: 0, truncated: false) != nil)
        #expect(AcceptanceValidation.axFailure(nodeCount: 3, truncated: true) != nil)
        #expect(AcceptanceValidation.axFailure(nodeCount: 3, truncated: false) == nil)
    }

    @Test func missingMeasurementsAndNoScrollFail() {
        func validate(bitmap: Bool = true, max: Double = 100, first: Double = 0, last: Double = 100,
                      before: UInt64? = 100, after: UInt64? = 100,
                      cpuBefore: Double? = 1, cpuAfter: Double? = 2) -> String? {
            AcceptanceValidation.measurementFailure(hasBitmap: bitmap, maxOffset: max, first: first, last: last,
                                                    physicalBefore: before, physicalAfter: after,
                                                    cpuBefore: cpuBefore, cpuAfter: cpuAfter)
        }
        #expect(validate() == nil)
        #expect(validate(bitmap: false) != nil)
        #expect(validate(max: 0, last: 0) != nil)
        #expect(validate(last: 80) != nil)
        #expect(validate(before: nil) != nil)
        #expect(validate(after: nil) != nil)
        #expect(validate(cpuBefore: nil) != nil)
        #expect(validate(cpuAfter: nil) != nil)
        #expect(validate(cpuAfter: 0) != nil)
    }
}
#endif
