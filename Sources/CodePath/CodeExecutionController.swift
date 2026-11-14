import ExecutionSupport
import Foundation
import Observation
import SwiftUI
import AppKit

@MainActor @Observable
final class CodeExecutionController {
    enum State: Equatable {
        case idle, verifying, phase(ExecutionPhase), stopping, finished
    }
    private(set) var state: State = .idle
    private(set) var result: ExecutionResult?
    private(set) var failure: ExecutionFailure?
    private(set) var backendFailure: ExecutionBackendFailure?
    private(set) var exerciseID: String?
    private(set) var sourceSnapshot = ""
    private(set) var inputSnapshot = ""
    var inputs: [String: String] = [:]
    private var task: Task<Void, Never>?
    private var cancellation: ExecutionCancellation?
    private var jobID: UUID?
    var isBusy: Bool { task != nil }

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

    @discardableResult
    func run(exerciseID: String, source: String, stdin: String) -> Bool {
        // One owner, one slot. Never spawn a second VM until the first helper is reaped.
        guard task == nil else { return false }
        let request = ExecutionRequest(source: source, stdin: stdin)
        self.exerciseID = exerciseID
        sourceSnapshot = source
        inputSnapshot = stdin
        result = nil
        failure = nil
        backendFailure = nil
        do { try request.validate() }
        catch { failure = .invalidRequest; state = .finished; return false }
        let assets: ExecutionAssets
        do { assets = try Self.bundledAssets() }
        catch { failure = error as? ExecutionFailure ?? .missingAssets; state = .finished; return false }
        let cancellation = ExecutionCancellation()
        self.cancellation = cancellation
        jobID = request.id
        state = .verifying
        let onPhase: @Sendable (ExecutionPhase) -> Void = { [weak self] phase in
            Task { @MainActor [weak self] in
                guard self?.jobID == request.id, self?.state != .stopping else { return }
                self?.state = .phase(phase)
            }
        }
        task = Task { [weak self] in
            let outcome = await Task.detached(priority: .userInitiated) {
                do {
                    return Result<ExecutionResult, ExecutionBackendFailure>.success(try ExecutionProcess.run(
                        request: request, assets: assets, cancellation: cancellation,
                        onPhase: onPhase))
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
            self.state = .finished
            self.task = nil
            self.cancellation = nil
            self.jobID = nil
        }
        return true
    }

    func cancel() {
        guard task != nil else { return }
        state = .stopping
        cancellation?.cancel()
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
