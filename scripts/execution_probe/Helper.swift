// Developer-only proof of isolation. Not linked to the application.
import Foundation
import Virtualization
import Darwin

struct Request: Decodable {
    let source: String
    let stdin: String
    let standard: String
}

struct Response: Encodable {
    let status: String
    let stdout: String
    let stderr: String
    let exitCode: Int?
    let detail: String
}

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
    private var signals: [DispatchSourceSignal] = []
    private var buffer = Data()
    private var consoleBytes = 0
    private var request: Request
    private var finishing = false
    private var sent = false
    private var pending: Response?

    init(request: Request, kernel: URL, initrd: URL) throws {
        self.request = request
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
            finish(Response(status: "timeout", stdout: "", stderr: "", exitCode: nil, detail: "Whole-VM wall limit"))
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
        for number in [SIGTERM, SIGINT] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { [self] in
                finish(Response(status: "cancelled", stdout: "", stderr: "", exitCode: nil, detail: "Host cancellation"))
            }
            source.resume()
            signals.append(source)
        }
        machine.start { [self] result in
            if case .failure(let error) = result {
                if let pending { emit(pending) }
                else { finish(Response(status: "backendError", stdout: "", stderr: "", exitCode: nil, detail: String(describing: error))) }
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
            finish(Response(status: "outputLimit", stdout: "", stderr: "", exitCode: nil, detail: "Bounded guest transport"))
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
        } else if line.hasPrefix("CODELIB_RESULT_1|") {
            let fields = line.split(separator: "|", omittingEmptySubsequences: false)
            let statuses = ["success", "compileError", "runtimeError", "cpuLimit", "outputLimit", "backendError"]
            guard fields.count == 5, statuses.contains(String(fields[1])),
                  sent || fields[1] == "backendError",
                  let code = Int(fields[2]), (-255...255).contains(code),
                  let out = Data(base64Encoded: String(fields[3])),
                  let err = Data(base64Encoded: String(fields[4])),
                  out.count <= Self.sourceLimit, err.count <= Self.sourceLimit else {
                finish(Response(status: "backendError", stdout: "", stderr: "", exitCode: nil, detail: "Invalid bounded guest response"))
                return
            }
            finish(Response(status: String(fields[1]), stdout: String(decoding: out, as: UTF8.self),
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
            emit(result)
        } else if machine.canStop {
            machine.stop { error in
                if let error {
                    emit(Response(status: "backendError", stdout: "", stderr: "", exitCode: nil,
                                  detail: "VM stop failed: \(error)"))
                } else { emit(result) }
            }
        } else {
            emit(Response(status: "backendError", stdout: "", stderr: "", exitCode: nil, detail: "VM cannot be stopped in its current state"))
        }
    }

    func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        if let pending { emit(pending) }
        else { finish(Response(status: "backendError", stdout: "", stderr: "", exitCode: nil, detail: "Guest stopped before result")) }
    }

    func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: Error) {
        finish(Response(status: "backendError", stdout: "", stderr: "", exitCode: nil, detail: String(describing: error)))
    }
}

func emit(_ result: Response) -> Never {
    if let data = try? JSONEncoder().encode(result) {
        FileHandle.standardOutput.write(data + Data([10]))
    }
    exit(result.status == "backendError" ? 1 : 0)
}

@main enum Main {
    static func main() {
        guard CommandLine.arguments.count == 3, VZVirtualMachine.isSupported else {
            emit(Response(status: "backendError", stdout: "", stderr: "", exitCode: nil, detail: "Usage: helper <kernel> <initrd>; virtualization required"))
        }
        do {
            var data = Data()
            while let chunk = try FileHandle.standardInput.read(upToCount: 16_384), !chunk.isEmpty {
                data.append(chunk)
                if data.count > 800_000 { break }
            }
            guard data.count <= 800_000 else { throw CocoaError(.fileReadTooLarge) }
            let request = try JSONDecoder().decode(Request.self, from: data)
            guard request.source.utf8.count <= ExecutionProbe.sourceLimit,
                  request.stdin.utf8.count <= ExecutionProbe.inputLimit,
                  ["17", "20"].contains(request.standard) else { throw CocoaError(.coderInvalidValue) }
            let probe = try ExecutionProbe(request: request, kernel: URL(fileURLWithPath: CommandLine.arguments[1]),
                                           initrd: URL(fileURLWithPath: CommandLine.arguments[2]))
            probe.start()
            withExtendedLifetime(probe) { dispatchMain() }
        } catch {
            emit(Response(status: "backendError", stdout: "", stderr: "", exitCode: nil, detail: String(describing: error)))
        }
    }
}
