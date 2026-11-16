import CryptoKit
import Darwin
import Foundation
import Security

public struct ExecutionAssets: Sendable {
    public let directory: URL
    public let helper: URL?
    public let application: URL?
    public init(directory: URL, helper: URL? = nil, application: URL? = nil) {
        self.directory = directory
        self.helper = helper
        self.application = application
    }
    // Reviewed outputs of the pinned Alpine artifacts + the trusted guest /init.
    // Changes require a deliberate rebuild, review and negative-test run.
    public static let images: [(name: String, bytes: Int, hash: String)] = [
        ("Image", 34_734_080, "2f3e223b93e5c827185a81f3d5abd3aff66bc0fcec3c8ad53deff4f6bcb9cb34"),
        ("initrd.gz", 119_333_957, "54b619ba87c149478f0f04f6140b1def5da2beb814249d4d679567999e08a9d8")
    ]

    public func validate() throws {
        guard directory.standardizedFileURL == directory.resolvingSymlinksInPath().standardizedFileURL else {
            throw ExecutionFailure.modifiedAssets
        }
        for image in Self.images {
            try Self.verifyFile(directory.appendingPathComponent(image.name), size: image.bytes, sha256: image.hash)
        }
        if let application { try Self.verifySignature(application, identifier: "local.codepath.learning", nested: true) }
        if let helper {
            guard helper.standardizedFileURL == helper.resolvingSymlinksInPath().standardizedFileURL else {
                throw ExecutionFailure.invalidHelper
            }
            try Self.verifySignature(helper, identifier: "local.codelib.execution-helper")
            var code: SecStaticCode?
            guard SecStaticCodeCreateWithPath(helper as CFURL, [], &code) == errSecSuccess, let code else {
                throw ExecutionFailure.invalidHelper
            }
            var info: CFDictionary?
            guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
                  let values = info as? [String: Any],
                  let entitlements = values[kSecCodeInfoEntitlementsDict as String] as? [String: Any],
                  entitlements["com.apple.security.virtualization"] as? Bool == true,
                  entitlements.count == 1 else { throw ExecutionFailure.invalidHelper }
        }
    }

    public static func verifyFile(_ url: URL, size: Int, sha256: String) throws {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else { throw errno == ENOENT ? ExecutionFailure.missingAssets : .modifiedAssets }
        defer { close(fd) }
        var before = stat()
        guard fstat(fd, &before) == 0, before.st_mode & S_IFMT == S_IFREG, before.st_size == size else {
            throw ExecutionFailure.modifiedAssets
        }
        var hash = SHA256()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        var total = 0
        while true {
            let count = read(fd, &buffer, buffer.count)
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                throw ExecutionFailure.modifiedAssets
            }
            total += count
            guard total <= size else { throw ExecutionFailure.modifiedAssets }
            hash.update(data: Data(buffer.prefix(count)))
        }
        var after = stat()
        guard fstat(fd, &after) == 0, total == size, before.st_ino == after.st_ino,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              hash.finalize().map({ String(format: "%02x", $0) }).joined() == sha256 else {
            throw ExecutionFailure.modifiedAssets
        }
    }

    private static func verifySignature(_ url: URL, identifier: String, nested: Bool = false) throws {
        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString("identifier \"\(identifier)\"" as CFString, [], &requirement) == errSecSuccess else {
            throw ExecutionFailure.invalidHelper
        }
        let flags = SecCSFlags(rawValue: kSecCSStrictValidate | (nested ? kSecCSCheckNestedCode : 0))
        guard SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess else {
            throw ExecutionFailure.invalidHelper
        }
    }
}
