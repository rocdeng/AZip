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

    func testKillsChildThatIgnoresSIGTERM() async throws {
        let start = ContinuousClock.now
        do {
            _ = try await ProcessRunner.run(
                "/bin/sh",
                ["-c", "trap '' TERM; sleep 30"],
                timeoutSeconds: 0.2
            )
            XCTFail("应当超时")
        } catch let error as ProcessRunnerError {
            XCTAssertEqual(error, .timedOut)
        }
        let elapsed = ContinuousClock.now - start
        XCTAssertLessThan(elapsed, .seconds(5), "超时后必须在有界时间内返回，实际耗时 \(elapsed)")
    }

    func testReturnsDespiteGrandchildHoldingPipe() async throws {
        let start = ContinuousClock.now
        do {
            let result = try await ProcessRunner.run(
                "/bin/sh",
                ["-c", "sleep 5 & echo hi"],
                timeoutSeconds: 0.5
            )
            XCTAssertEqual(result.status, 0)
        } catch let error as ProcessRunnerError {
            XCTAssertEqual(error, .timedOut)
        }
        let elapsed = ContinuousClock.now - start
        XCTAssertLessThan(elapsed, .seconds(3), "孙进程持有 pipe 时也必须有界返回，实际耗时 \(elapsed)")
    }

    func testCapturesLargeOutputWithoutDeadlock() async throws {
        let result = try await ProcessRunner.run("/bin/sh", ["-c", "seq 1 200000"])
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.stdout.split(separator: "\n").count, 200000)
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
