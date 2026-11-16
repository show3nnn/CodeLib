import Darwin
import Foundation

public final class ExecutionCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    public init() {}
    public func cancel() { lock.withLock { value = true } }
    public var isCancelled: Bool { lock.withLock { value } }
}

public struct ExecutionEventDecoder {
    private var buffer = Data()
    private var bytes = 0
    private var lastPhase: ExecutionPhase?
    public private(set) var result: ExecutionResult?
    private let id: UUID
    public init(id: UUID) { self.id = id }
    public mutating func feed(_ data: Data) throws -> [ExecutionPhase] {
        bytes += data.count
        guard bytes <= ExecutionLimits.transport else { throw ExecutionFailure.invalidResponse }
        buffer.append(data)
        var phases: [ExecutionPhase] = []
        while let end = buffer.firstIndex(of: 10) {
            guard result == nil else { throw ExecutionFailure.invalidResponse }
            let line = buffer[..<end]
            let event: ExecutionEvent
            do { event = try JSONDecoder().decode(ExecutionEvent.self, from: line) }
            catch { throw ExecutionFailure.invalidResponse }
            try event.validate(for: id)
            if let phase = event.phase {
                let allowed: Bool = switch phase {
                case .booting: lastPhase == nil
                case .compiling: lastPhase == .booting
                case .running: lastPhase == .compiling
                }
                guard allowed else { throw ExecutionFailure.invalidResponse }
                lastPhase = phase
                phases.append(phase)
            }
            if let result = event.result {
                if (result.status == .success || result.status == .fileMismatch) && lastPhase != .running {
                    throw ExecutionFailure.invalidResponse
                }
                if result.status == .compileError && lastPhase != .compiling { throw ExecutionFailure.invalidResponse }
                self.result = result
            }
            buffer.removeSubrange(...end)
        }
        return phases
    }
    public func finish() throws -> ExecutionResult {
        guard buffer.isEmpty, let result else { throw ExecutionFailure.invalidResponse }
        return result
    }
}

public enum ExecutionProcess {
    /// Synchronous bounded I/O pump; call off the main actor. Only the signed helper
    /// is spawned on macOS. The source is data; no user executable or shell is run.
    public static func run(
        request: ExecutionRequest, assets: ExecutionAssets, cancellation: ExecutionCancellation,
        onPhase: @Sendable (ExecutionPhase) -> Void
    ) throws -> ExecutionResult {
        try request.validate()
        if cancellation.isCancelled { return ExecutionResult(status: .cancelled) }
        try assets.validate()
        guard let helper = assets.helper else { throw ExecutionFailure.invalidHelper }
        if cancellation.isCancelled { return ExecutionResult(status: .cancelled) }
        let process = Process()
        let input = Pipe(), output = Pipe(), errors = Pipe()
        process.executableURL = helper
        process.arguments = [assets.directory.path]
        process.environment = ["PATH": "/usr/bin:/bin", "LANG": "C"]
        process.currentDirectoryURL = assets.directory
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        let data = try JSONEncoder().encode(request)
        guard data.count <= ExecutionLimits.request else { throw ExecutionFailure.invalidRequest }
        do { try process.run() }
        catch { throw ExecutionBackendFailure(reason: .launchFailed, cause: error) }
        // Parent must close its child ends; otherwise EOF cannot be observed.
        try? input.fileHandleForReading.close()
        try? output.fileHandleForWriting.close()
        try? errors.fileHandleForWriting.close()
        let writer = input.fileHandleForWriting
        let stdout = output.fileHandleForReading, stderr = errors.fileHandleForReading
        defer {
            try? writer.close(); try? stdout.close(); try? stderr.close()
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
        }
        for handle in [writer, stdout, stderr] {
            let fd = handle.fileDescriptor
            guard fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) == 0 else {
                throw ExecutionFailure.transportFailed
            }
        }
        guard fcntl(writer.fileDescriptor, F_SETNOSIGPIPE, 1) == 0 else { throw ExecutionFailure.transportFailed }
        var decoder = ExecutionEventDecoder(id: request.id)
        var offset = 0
        var inputClosed = false
        var outputClosed = false
        var errorsClosed = false
        var errorBytes = 0
        let start = ContinuousClock.now
        var cancelledAt: ContinuousClock.Instant?
        var failure: ExecutionFailure?
        while process.isRunning || !outputClosed || !errorsClosed {
            let elapsed = start.duration(to: .now)
            if cancellation.isCancelled || elapsed >= .seconds(40) || failure != nil {
                if cancelledAt == nil {
                    cancelledAt = .now
                    if elapsed >= .seconds(40) { failure = .deadline }
                    if process.isRunning { process.terminate() }
                } else if cancelledAt!.duration(to: .now) >= .seconds(2), process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
            }
            var descriptors = [
                pollfd(fd: outputClosed ? -1 : stdout.fileDescriptor, events: Int16(POLLIN), revents: 0),
                pollfd(fd: errorsClosed ? -1 : stderr.fileDescriptor, events: Int16(POLLIN), revents: 0),
                pollfd(fd: inputClosed ? -1 : writer.fileDescriptor, events: Int16(POLLOUT), revents: 0)
            ]
            if poll(&descriptors, nfds_t(descriptors.count), 50) < 0 && errno != EINTR {
                failure = .transportFailed
            }
            if !inputClosed && descriptors[2].revents != 0 {
                if offset < data.count && cancelledAt == nil {
                    let count = data.withUnsafeBytes { bytes in
                        write(writer.fileDescriptor, bytes.baseAddress!.advanced(by: offset), min(16_384, data.count - offset))
                    }
                    if count > 0 { offset += count }
                    else if count < 0 && errno != EAGAIN && errno != EINTR { failure = .transportFailed }
                }
                if offset == data.count || cancelledAt != nil || failure != nil {
                    try? writer.close()
                    inputClosed = true
                }
            }
            for index in 0...1 where descriptors[index].revents != 0 {
                var bytes = [UInt8](repeating: 0, count: 16_384)
                let fd = index == 0 ? stdout.fileDescriptor : stderr.fileDescriptor
                let count = read(fd, &bytes, bytes.count)
                if count == 0 {
                    if index == 0 { outputClosed = true } else { errorsClosed = true }
                } else if count > 0 {
                    if index == 0 && failure == nil {
                        do {
                            for phase in try decoder.feed(Data(bytes.prefix(count))) { onPhase(phase) }
                        } catch { failure = .invalidResponse }
                    } else if index == 1 {
                        errorBytes += count
                        if errorBytes > ExecutionLimits.stream { failure = .invalidResponse }
                        // Host diagnostics never become commands, paths or unbounded UI text.
                    }
                } else if errno != EAGAIN && errno != EINTR {
                    failure = .transportFailed
                    if index == 0 { outputClosed = true } else { errorsClosed = true }
                }
            }
            if !process.isRunning && inputClosed == false { try? writer.close(); inputClosed = true }
        }
        process.waitUntilExit()
        if let failure { throw failure }
        if cancellation.isCancelled { return ExecutionResult(status: .cancelled) }
        let result = try decoder.finish()
        guard process.terminationReason == .exit,
              process.terminationStatus == (result.status == .backendError ? 1 : 0) else {
            throw ExecutionFailure.transportFailed
        }
        return result
    }
}
