import CryptoKit
import Foundation
import Testing
@testable import ExecutionSupport

struct ExecutionSupportTests {
    private func scratch() throws -> URL {
        let parent = ProcessInfo.processInfo.environment["CODEPATH_TEST_ROOT"]
            ?? FileManager.default.currentDirectoryPath + "/.build/test-data"
        let folder = URL(fileURLWithPath: parent).appendingPathComponent("execution-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CODELIB_EXECUTION_TEST_APP"] != nil))
    func packagedSignaturesFailClosed() throws {
        let application = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["CODELIB_EXECUTION_TEST_APP"]))
        let directory = application.appendingPathComponent("Contents/Resources/ExecutionGuest")
        let helper = application.appendingPathComponent("Contents/Helpers/CodelibExecutionHelper")
        try ExecutionAssets(directory: directory, helper: helper, application: application).validate()
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let fake = folder.appendingPathComponent("helper")
        try Data("unsigned helper".utf8).write(to: fake)
        #expect(throws: ExecutionFailure.invalidHelper) { try ExecutionAssets(directory: directory, helper: fake).validate() }
        #expect(throws: ExecutionFailure.invalidHelper) { try ExecutionAssets(directory: directory, helper: helper, application: folder).validate() }
    }

    @Test func requestLimitsAndStandards() throws {
        try ExecutionRequest(source: "", stdin: "").validate()
        try ExecutionRequest(source: String(repeating: "x", count: 65_536), stdin: "", standard: "20").validate()
        for request in [ExecutionRequest(source: "", stdin: "", standard: "17;echo bad"),
                        ExecutionRequest(source: String(repeating: "x", count: 65_537), stdin: ""),
                        ExecutionRequest(source: "", stdin: String(repeating: "x", count: 65_537))] {
            #expect(throws: ExecutionFailure.invalidRequest) { try request.validate() }
        }
    }

    @Test func fileFixturesValidateNamesSizesAndCounts() throws {
        try ExecutionRequest(source: "", stdin: "", files: ["journal.txt": "0\n"],
                             expectedFiles: ["journal.txt": "1\n"]).validate()
        // Names stay plain path components and never collide with trusted files.
        for name in ["", ".", "..", "main.cpp", "stdin", "program", "a/b", "../x", "/abs",
                     "name with space", "emoji😀", String(repeating: "n", count: 65)] {
            #expect(throws: ExecutionFailure.invalidRequest) {
                try ExecutionRequest(source: "", stdin: "", files: [name: "1"]).validate()
            }
        }
        #expect(ExecutionFiles.isValidName(String(repeating: "n", count: 64)))
        #expect(ExecutionFiles.isValidName("A-Za-z0-9._-"))
        // Per-file, total and count limits fail closed.
        #expect(throws: ExecutionFailure.invalidRequest) {
            try ExecutionRequest(source: "", stdin: "", files: ["a.txt": String(repeating: "x", count: 65_537)]).validate()
        }
        #expect(throws: ExecutionFailure.invalidRequest) {
            try ExecutionRequest(source: "", stdin: "", files: ["a.txt": String(repeating: "x", count: 32_768),
                                                               "b.txt": String(repeating: "x", count: 32_769)]).validate()
        }
        var many: [String: String] = [:]
        for index in 0..<9 { many["file\(index).txt"] = "1" }
        #expect(throws: ExecutionFailure.invalidRequest) {
            try ExecutionRequest(source: "", stdin: "", files: many).validate()
        }
        #expect(throws: ExecutionFailure.invalidRequest) {
            try ExecutionRequest(source: "", stdin: "", expectedFiles: ["../escape": "1"]).validate()
        }
    }

    @Test func fileMismatchResultIsBoundedAndPhaseChecked() throws {
        let id = UUID()
        var decoder = ExecutionEventDecoder(id: id)
        for phase in [ExecutionPhase.booting, .compiling, .running] {
            _ = try decoder.feed(JSONEncoder().encode(ExecutionEvent(id: id, phase: phase)) + Data([10]))
        }
        let good = ExecutionEvent(id: id, result: ExecutionResult(
            status: .fileMismatch, stdout: "Saved", exitCode: 0, detail: "d", fileDetail: "journal.txt"))
        _ = try decoder.feed(JSONEncoder().encode(good) + Data([10]))
        let result = try decoder.finish()
        #expect(result.status == .fileMismatch && result.fileDetail == "journal.txt")
        try result.validate()
        // fileMismatch without phase context, without exit code or without names fails closed.
        for broken in [ExecutionEvent(id: id, result: ExecutionResult(status: .fileMismatch, exitCode: 0, detail: "d")),
                       ExecutionEvent(id: id, result: ExecutionResult(status: .fileMismatch, exitCode: 1, detail: "d", fileDetail: "a")),
                       ExecutionEvent(id: id, result: ExecutionResult(status: .fileMismatch, exitCode: 0, detail: "d", fileDetail: String(repeating: "x", count: 2049)))] {
            var check = ExecutionEventDecoder(id: id)
            #expect(throws: ExecutionFailure.invalidResponse) {
                _ = try check.feed(JSONEncoder().encode(ExecutionEvent(id: id, phase: .running)) + Data([10]))
                _ = try check.feed(JSONEncoder().encode(broken) + Data([10]))
            }
        }
    }

    @Test func fragmentedProtocolAndFailClosedResponses() throws {
        let id = UUID()
        let events = [ExecutionEvent(id: id, phase: .booting), ExecutionEvent(id: id, phase: .compiling),
                      ExecutionEvent(id: id, phase: .running),
                      ExecutionEvent(id: id, result: ExecutionResult(status: .success, stdout: "Привет %@", exitCode: 0))]
        let data = try events.reduce(into: Data()) { $0.append(try JSONEncoder().encode($1)); $0.append(10) }
        var decoder = ExecutionEventDecoder(id: id)
        for byte in data { _ = try decoder.feed(Data([byte])) }
        #expect(try decoder.finish().stdout == "Привет %@")
        #expect(throws: ExecutionFailure.invalidResponse) { try decoder.feed(Data("{}\n".utf8)) }
        for event in [ExecutionEvent(id: UUID(), phase: .booting),
                      ExecutionEvent(id: id, phase: .running),
                      ExecutionEvent(id: id, result: ExecutionResult(status: .success, exitCode: 0)),
                      ExecutionEvent(id: id, result: ExecutionResult(status: .success, exitCode: 1))] {
            var broken = ExecutionEventDecoder(id: id)
            #expect(throws: ExecutionFailure.invalidResponse) {
                try broken.feed(JSONEncoder().encode(event) + Data([10]))
            }
        }
        var truncated = ExecutionEventDecoder(id: id)
        _ = try truncated.feed(Data("{".utf8))
        #expect(throws: ExecutionFailure.invalidResponse) { try truncated.finish() }
    }

    @Test func assetsRejectModificationAndSymlink() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("image")
        let data = Data("trusted".utf8)
        try data.write(to: file)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        try ExecutionAssets.verifyFile(file, size: data.count, sha256: digest)
        try Data("changed".utf8).write(to: file)
        #expect(throws: ExecutionFailure.modifiedAssets) { try ExecutionAssets.verifyFile(file, size: data.count, sha256: digest) }
        let link = folder.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        #expect(throws: ExecutionFailure.modifiedAssets) { try ExecutionAssets.verifyFile(link, size: data.count, sha256: digest) }
    }

    @Test func diagnosticsPreserveLiteralTextAndPosition() {
        let diagnostics = CompilerDiagnostic.parse("/work/main.cpp:2:9: error: missing «🚀» %@\nunknown:3:4: error: ignore")
        #expect(diagnostics.count == 1)
        #expect(diagnostics.first?.line == 2 && diagnostics.first?.column == 9)
        #expect(diagnostics.first?.message == "missing «🚀» %@")
    }
}
