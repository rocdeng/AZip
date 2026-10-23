import XCTest
@testable import AZipCore

final class ProcessRunnerTests: XCTestCase {
    func testCapturesStdout() async throws {
        let result = try await ProcessRunner.run("/bin/echo", ["hello"])
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "hello")
    }

    func testCapturesStderrAndStatus() async throws {
        let result = try await ProcessRunner.run("/bin/sh", ["-c", "echo boom >&2; exit 3"])
        XCTAssertEqual(result.status, 3)
        XCTAssertTrue(result.stderr.contains("boom"))
    }

    func testTimesOut() async throws {
        do {
            _ = try await ProcessRunner.run("/bin/sleep", ["5"], timeoutSeconds: 0.3)
            XCTFail("应当超时")
        } catch let error as ProcessRunnerError {
            guard case .timedOut = error else {
                return XCTFail("错误类型不符：\(error)")
            }
        }
    }

    func testLaunchFailure() async throws {
        do {
            _ = try await ProcessRunner.run("/nonexistent/binary", [])
            XCTFail("应当抛错")
        } catch let error as ProcessRunnerError {
            guard case .launchFailed = error else {
                return XCTFail("错误类型不符：\(error)")
            }
        }
    }
}
