// The host launches only this trusted helper, never a user-generated native executable.
import Foundation
import Virtualization
import Darwin
#if canImport(ExecutionSupport)
import ExecutionSupport
#endif
typealias Request = ExecutionRequest
typealias Response = ExecutionResult

final class ExecutionProbe: NSObject, VZVirtualMachineDelegate {
    // Limits are host policy, never fields supplied by source code or guest output.
    static let sourceLimit = 65_536
    static let inputLimit = 65_536
    static let consoleLimit = 262_144
    private let input = Pipe()
    private let output = Pipe()
    private var machine: VZVirtualMachine!
    private var reader: DispatchSourceRead?
    private var deadline: DispatchSourceTimer?
    private var watchdog: DispatchSourceTimer?
    private var parentWatch: DispatchSourceTimer?
    private var signals: [DispatchSourceSignal] = []
    private var buffer = Data()
    private var consoleBytes = 0
    private var request: Request
    private var finishing = false
    private var sent = false
    private var pending: Response?
    private let ownerPID: pid_t

    init(request: Request, kernel: URL, initrd: URL, ownerPID: pid_t) throws {
        self.request = request
        self.ownerPID = ownerPID
        super.init()
        let boot = VZLinuxBootLoader(kernelURL: kernel)
        boot.initialRamdiskURL = initrd
        boot.commandLine = "console=hvc0 quiet loglevel=0 panic=1 rdinit=/init"
        let port = VZVirtioConsoleDeviceSerialPortConfiguration()
        port.attachment = VZFileHandleSerialPortAttachment(
            fileHandleForReading: input.fileHandleForReading,
            fileHandleForWriting: output.fileHandleForWriting)
        let configuration = VZVirtualMachineConfiguration()
        configuration.bootLoader = boot
        configuration.cpuCount = 1
        configuration.memorySize = 1024 * 1024 * 1024
        configuration.serialPorts = [port]
        // Deliberately NO network, disks, shared directories, vsock or host devices.
        configuration.networkDevices = []
        configuration.storageDevices = []
        configuration.directorySharingDevices = []
        configuration.socketDevices = []
        try configuration.validate()
        machine = VZVirtualMachine(configuration: configuration)
        machine.delegate = self
    }

    func start() {
        let fd = output.fileHandleForReading.fileDescriptor
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [self] in readConsole() }
        source.resume()
        reader = source
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .seconds(30))
        timer.setEventHandler { [self] in
            finish(Response(status: .timeout, detail: "Whole-VM wall limit"))
        }
        timer.resume()
        deadline = timer
        // Last resort if the framework/VM queue itself fails to complete a stop.
        // No success response is emitted; the harness treats exit 124 as backend failure.
        // Destroying the owner process also destroys its non-persistent VM.
        let hardTimer = DispatchSource.makeTimerSource(queue: .global())
        hardTimer.schedule(deadline: .now() + .seconds(35))
        hardTimer.setEventHandler { _exit(124) }
        hardTimer.resume()
        watchdog = hardTimer
        let parent = ownerPID
        let parentTimer = DispatchSource.makeTimerSource(queue: .main)
        parentTimer.schedule(deadline: .now(), repeating: .milliseconds(250))
        parentTimer.setEventHandler { [self] in
            if getppid() != parent { finish(Response(status: .cancelled, detail: "Owner process exited")) }
        }
        parentTimer.resume()
        parentWatch = parentTimer
        for number in [SIGTERM, SIGINT] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { [self] in
                finish(Response(status: .cancelled, detail: "Host cancellation"))
            }
            source.resume()
            signals.append(source)
        }
        send(ExecutionEvent(id: request.id, phase: .booting))
        machine.start { [self] result in
            if case .failure(let error) = result {
                if let pending { emitResult(pending) }
                else { finish(Response(status: .backendError, detail: String(describing: error))) }
            } else if let pending {
                stopAndEmit(pending)
            }
        }
    }

    private func readConsole() {
        guard !finishing else { return }
        var bytes = [UInt8](repeating: 0, count: 16_384)
        let count = read(output.fileHandleForReading.fileDescriptor, &bytes, bytes.count)
        guard count > 0 else { return }
        consoleBytes += count
        guard consoleBytes <= Self.consoleLimit else {
            finish(Response(status: .outputLimit, detail: "Bounded guest transport"))
            return
        }
        buffer.append(contentsOf: bytes.prefix(count))
        while let end = buffer.firstIndex(of: 10) {
            let line = String(decoding: buffer[..<end], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            buffer.removeSubrange(...end)
            handle(line)
            if finishing { return }
        }
    }

    private func handle(_ line: String) {
        if line == "CODELIB_READY_1" && !sent {
            sent = true
            // Both lines are base64, never interpolated into a host/guest shell command.
            let text = request.standard + "\n" + Data(request.source.utf8).base64EncodedString()
                + "\n" + Data(request.stdin.utf8).base64EncodedString() + "\n"
            let data = Data(text.utf8)
            // A serial write can block if a guest stops reading. Keep it off the VM queue.
            let handle = input.fileHandleForWriting
            DispatchQueue.global().async { try? handle.write(contentsOf: data) }
        } else if sent && line.hasPrefix("CODELIB_PHASE_1|") {
            let value = String(line.dropFirst("CODELIB_PHASE_1|".count))
            if let phase = ExecutionPhase(rawValue: value), phase != .booting {
                send(ExecutionEvent(id: request.id, phase: phase))
            }
        } else if line.hasPrefix("CODELIB_RESULT_1|") {
            let fields = line.split(separator: "|", omittingEmptySubsequences: false)
            guard fields.count == 5, let status = ExecutionStatus(rawValue: String(fields[1])),
                  sent || fields[1] == "backendError",
                  let code = Int(fields[2]), (-255...255).contains(code),
                  let out = Data(base64Encoded: String(fields[3])),
                  let err = Data(base64Encoded: String(fields[4])),
                  out.count <= Self.sourceLimit, err.count <= Self.sourceLimit else {
                finish(Response(status: .backendError, detail: "Invalid bounded guest response"))
                return
            }
            finish(Response(status: status, stdout: String(decoding: out, as: UTF8.self),
                            stderr: String(decoding: err, as: UTF8.self), exitCode: code, detail: "Ephemeral Linux VM"))
        }
        // Kernel/APK boot messages are data, not protocol responses or instructions.
    }

    private func finish(_ result: Response) {
        guard !finishing else { return }
        finishing = true
        pending = result
        deadline?.cancel()
        reader?.cancel()
        if machine.state == .starting {
            // stop() is valid only after start has completed.
            return
        }
        stopAndEmit(result)
    }

    private func stopAndEmit(_ result: Response) {
        // Forced VM stop, NOT a guest requestStop() which malicious code could ignore.
        if machine.state == .stopped || machine.state == .error {
            emitResult(result)
        } else if machine.canStop {
            machine.stop { [self] error in
                if let error {
                    emitResult(Response(status: .backendError, detail: "VM stop failed: \(error)"))
                } else { emitResult(result) }
            }
        } else {
            emitResult(Response(status: .backendError, detail: "VM cannot be stopped in its current state"))
        }
    }

    func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        if let pending { emitResult(pending) }
        else { finish(Response(status: .backendError, detail: "Guest stopped before result")) }
    }

    func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: Error) {
        finish(Response(status: .backendError, detail: String(describing: error)))
    }

    private func emitResult(_ result: Response) -> Never {
        send(ExecutionEvent(id: request.id, result: result))
        exit(result.status == .backendError ? 1 : 0)
    }
}

func send(_ event: ExecutionEvent) {
    if let data = try? JSONEncoder().encode(event) { FileHandle.standardOutput.write(data + Data([10])) }
}

@main enum Main {
    static func main() {
        let ownerPID = getppid()
        do {
            if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--verify-assets" {
                try ExecutionAssets(directory: URL(fileURLWithPath: CommandLine.arguments[2])).validate()
                print("Execution guest SHA256 verified")
                exit(0)
            }
            guard CommandLine.arguments.count == 2, VZVirtualMachine.isSupported else { throw ExecutionFailure.unavailable }
            var data = Data()
            while let chunk = try FileHandle.standardInput.read(upToCount: 16_384), !chunk.isEmpty {
                data.append(chunk)
                if data.count > 800_000 { break }
            }
            guard data.count <= 800_000 else { throw CocoaError(.fileReadTooLarge) }
            let request = try JSONDecoder().decode(Request.self, from: data)
            try request.validate()
            let assets = ExecutionAssets(directory: URL(fileURLWithPath: CommandLine.arguments[1]))
            try assets.validate()
            guard ownerPID > 1, getppid() == ownerPID else { throw ExecutionFailure.transportFailed }
            let probe = try ExecutionProbe(request: request, kernel: assets.directory.appendingPathComponent("Image"),
                                           initrd: assets.directory.appendingPathComponent("initrd.gz"), ownerPID: ownerPID)
            probe.start()
            withExtendedLifetime(probe) { dispatchMain() }
        } catch {
            send(ExecutionEvent(id: nil, result: Response(status: .backendError, detail: String(describing: error))))
            exit(1)
        }
    }
}
