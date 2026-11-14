import ExecutionSupport
import Foundation
import LearningCore
import Observation
import SwiftUI
import AppKit

/// Result of one grading fixture. Kept in memory only; progress already stores the
/// compact attempts/lastCorrect/completion summary.
struct GradingCaseResult: Identifiable, Sendable, Equatable {
    let index: Int
    let input: String
    let expectedOutput: String
    let actualOutput: String
    let stderr: String
    let status: ExecutionStatus
    let exitCode: Int?
    let matches: Bool
    var id: Int { index }

    var ranProgram: Bool { status == .success }
}

@MainActor @Observable
final class CodeExecutionController {
    enum Readiness: Equatable {
        case unchecked, checking, ready, failed, cancelled
    }
    static func readinessOutcome(result: ExecutionResult?, cancelled: Bool) -> Readiness {
        if cancelled || result?.status == .cancelled { return .cancelled }
        guard let result, result.status == .success, result.exitCode == 0,
              result.stdout == "codelib-ready" else { return .failed }
        return .ready
    }
    enum State: Equatable {
        case idle, verifying, phase(ExecutionPhase), stopping, finished
    }
    private(set) var state: State = .idle
    private(set) var readiness: Readiness = .unchecked
    private(set) var result: ExecutionResult?
    private(set) var failure: ExecutionFailure?
    private(set) var backendFailure: ExecutionBackendFailure?
    private(set) var exerciseID: String?
    private(set) var sourceSnapshot = ""
    private(set) var inputSnapshot = ""
    private(set) var isGrading = false
    private(set) var gradingCaseIndex = 0
    private(set) var gradingCaseTotal = 0
    private(set) var gradingResults: [GradingCaseResult] = []
    var inputs: [String: String] = [:]
    private var task: Task<Void, Never>?
    private var cancellation: ExecutionCancellation?
    private var jobID: UUID?
    private var onGradingFinished: ((_ exerciseID: String, _ passed: Bool) -> Void)?
    var isBusy: Bool { task != nil }

    var gradingPassed: Bool {
        isGrading && gradingCaseTotal > 0 && gradingResults.count == gradingCaseTotal
            && gradingResults.allSatisfy(\.matches)
    }

    static func bundledAssets() throws -> ExecutionAssets {
        #if !arch(arm64)
        throw ExecutionFailure.unavailable
        #else
        let bundle = Bundle.main
        guard bundle.bundleURL.pathExtension == "app", let resources = bundle.resourceURL else {
            throw ExecutionFailure.missingAssets
        }
        return ExecutionAssets(
            directory: resources.appendingPathComponent("ExecutionGuest"),
            helper: bundle.bundleURL.appendingPathComponent("Contents/Helpers/CodelibExecutionHelper"),
            application: bundle.bundleURL
        )
        #endif
    }

    /// The same single slot and verified helper are used as for user programs.
    /// A successful compiler invocation alone is not sufficient: check its output too.
    @discardableResult
    func checkReadiness() -> Bool {
        guard task == nil else { return false }
        let request = ExecutionRequest(source: "#include <iostream>\nint main() { std::cout << \"codelib-ready\"; }\n", stdin: "")
        let assets: ExecutionAssets
        do { assets = try Self.bundledAssets() }
        catch {
            readiness = .failed
            return false
        }
        let cancellation = ExecutionCancellation()
        self.cancellation = cancellation
        jobID = request.id
        readiness = .checking
        state = .verifying
        task = Task { [weak self] in
            let outcome = await Task.detached(priority: .userInitiated) {
                Result { try ExecutionProcess.run(request: request, assets: assets, cancellation: cancellation, onPhase: { _ in }) }
            }.value
            guard let self, self.jobID == request.id else { return }
            let result = try? outcome.get()
            self.readiness = Self.readinessOutcome(result: result, cancelled: cancellation.isCancelled)
            self.finish()
        }
        return true
    }

    @discardableResult
    func run(exerciseID: String, source: String, stdin: String) -> Bool {
        // One owner, one slot. Never spawn a second VM until the first helper is reaped.
        guard task == nil else { return false }
        let request = ExecutionRequest(source: source, stdin: stdin)
        reset(exerciseID: exerciseID, source: source, input: stdin, grading: false)
        do { try request.validate() }
        catch { failure = .invalidRequest; state = .finished; return false }
        let assets: ExecutionAssets
        do { assets = try Self.bundledAssets() }
        catch { failure = error as? ExecutionFailure ?? .missingAssets; state = .finished; return false }
        let cancellation = ExecutionCancellation()
        self.cancellation = cancellation
        jobID = request.id
        state = .verifying
        task = Task { [weak self] in
            let outcome = await Task.detached(priority: .userInitiated) {
                do {
                    return Result<ExecutionResult, ExecutionBackendFailure>.success(try ExecutionProcess.run(
                        request: request, assets: assets, cancellation: cancellation,
                        onPhase: Self.phaseForwarder(job: request.id, controller: self)))
                } catch let error as ExecutionBackendFailure { return .failure(error) }
                catch { return .failure(ExecutionBackendFailure(reason: error as? ExecutionFailure ?? .transportFailed, cause: error)) }
            }.value
            guard let self, self.jobID == request.id else { return }
            switch outcome {
            case .success(let result): self.result = result
            case .failure(let failure):
                self.failure = failure.reason
                self.backendFailure = failure
            }
            self.finish()
        }
        return true
    }

    /// Runs every verified fixture sequentially in fresh isolated VMs. Only a complete
    /// run of all fixtures can mark the exercise automatically; execution itself never does.
    @discardableResult
    func grade(exerciseID: String, source: String, fixtures: [GradingFixture],
               onFinished: @escaping (String, Bool) -> Void) -> Bool {
        guard task == nil, !fixtures.isEmpty else { return false }
        guard fixtures.allSatisfy({ ExecutionRequest(source: source, stdin: $0.input).validateSafely() }) else {
            reset(exerciseID: exerciseID, source: source, input: "", grading: true)
            failure = .invalidRequest
            state = .finished
            return false
        }
        let assets: ExecutionAssets
        do { assets = try Self.bundledAssets() }
        catch {
            reset(exerciseID: exerciseID, source: source, input: "", grading: true)
            failure = error as? ExecutionFailure ?? .missingAssets
            state = .finished
            return false
        }
        reset(exerciseID: exerciseID, source: source, input: "", grading: true)
        gradingCaseTotal = fixtures.count
        gradingCaseIndex = 0
        onGradingFinished = onFinished
        let cancellation = ExecutionCancellation()
        self.cancellation = cancellation
        let job = UUID()
        jobID = job
        state = .verifying
        task = Task { [weak self] in
            let outcome = await Task.detached(priority: .userInitiated) { () -> Result<[GradingCaseResult], ExecutionBackendFailure> in
                var collected: [GradingCaseResult] = []
                for fixture in fixtures {
                    if cancellation.isCancelled {
                        return .success(collected)
                    }
                    let request = ExecutionRequest(source: source, stdin: fixture.input)
                    do {
                        let result = try ExecutionProcess.run(
                            request: request, assets: assets, cancellation: cancellation,
                            onPhase: Self.phaseForwarder(job: job, controller: self))
                        let item = GradingCaseResult(
                            index: fixture.index, input: fixture.input,
                            expectedOutput: fixture.expectedOutput, actualOutput: result.stdout,
                            stderr: result.stderr, status: result.status,
                            exitCode: result.exitCode,
                            matches: result.status == .success
                                && OutputComparison.matches(result.stdout, expected: fixture.expectedOutput))
                        collected.append(item)
                        await MainActor.run { [weak self] in
                            guard let self, self.jobID == job else { return }
                            self.gradingCaseIndex = fixture.index
                            self.gradingResults.append(item)
                        }
                        if result.status == .cancelled { return .success(collected) }
                    } catch let error as ExecutionBackendFailure {
                        return .failure(error)
                    } catch {
                        return .failure(ExecutionBackendFailure(reason: error as? ExecutionFailure ?? .transportFailed, cause: error))
                    }
                }
                return .success(collected)
            }.value
            guard let self, self.jobID == job else { return }
            switch outcome {
            case .success(let results):
                self.gradingResults = results
                self.gradingCaseIndex = results.count
                let completed = results.count == fixtures.count && results.allSatisfy { $0.status != .cancelled }
                self.finish()
                if completed { self.onGradingFinished?(exerciseID, results.allSatisfy(\.matches)) }
                self.onGradingFinished = nil
            case .failure(let failure):
                self.failure = failure.reason
                self.backendFailure = failure
                self.finish()
                self.onGradingFinished = nil
            }
        }
        return true
    }

    func cancel() {
        guard task != nil else { return }
        state = .stopping
        cancellation?.cancel()
    }

    private func reset(exerciseID: String, source: String, input: String, grading: Bool) {
        self.exerciseID = exerciseID
        sourceSnapshot = source
        inputSnapshot = input
        result = nil
        failure = nil
        backendFailure = nil
        isGrading = grading
        gradingCaseIndex = 0
        gradingCaseTotal = 0
        gradingResults = []
    }

    private func finish() {
        state = .finished
        task = nil
        cancellation = nil
        jobID = nil
    }

    private nonisolated static func phaseForwarder(job: UUID, controller: CodeExecutionController?) -> @Sendable (ExecutionPhase) -> Void {
        { [controller] phase in
            Task { @MainActor in
                guard let controller, controller.jobID == job, controller.state != .stopping else { return }
                controller.state = .phase(phase)
            }
        }
    }
}

private extension ExecutionRequest {
    /// Cheap pre-flight for a batch; the real validation also runs per request.
    func validateSafely() -> Bool {
        (try? validate()) != nil
    }
}

/// Observe the actual hosting window without replacing SwiftUI's window delegate.
struct ExecutionWindowObserver: NSViewRepresentable {
    let onClose: () -> Void
    func makeNSView(context: Context) -> WindowView { WindowView() }
    func updateNSView(_ view: WindowView, context: Context) { view.onClose = onClose }
    static func dismantleNSView(_ view: WindowView, coordinator: ()) { view.stopObserving() }
    final class WindowView: NSView {
        var onClose: (() -> Void)?
        private var observer: NSObjectProtocol?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopObserving()
            if let window {
                observer = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.onClose?() }
                }
            }
        }
        func stopObserving() {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
        }
    }
}
