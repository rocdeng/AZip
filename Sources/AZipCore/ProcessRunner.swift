import Darwin
import Foundation

public enum ProcessRunnerError: Error, Sendable, Equatable {
    case launchFailed(String)
    case timedOut
}

public enum ProcessRunner {
    public struct Result: Sendable {
        public let status: Int32
        public let stdout: String
        public let stderr: String

        public init(status: Int32, stdout: String, stderr: String) {
            self.status = status
            self.stdout = stdout
            self.stderr = stderr
        }
    }

    /// 保证等待的两个分支（读取完成 / 到达截止时间）中只有一方恢复 continuation。
    private actor ResumeGate {
        private var resumed = false

        func claim() -> Bool {
            guard !resumed else { return false }
            resumed = true
            return true
        }
    }

    public static func run(
        _ executable: String,
        _ arguments: [String],
        standardInput: String? = nil,
        timeoutSeconds: Double = 60
    ) async throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let inPipe = Pipe()
        process.standardInput = standardInput == nil ? FileHandle.nullDevice : inPipe

        do {
            try process.run()
        } catch {
            throw ProcessRunnerError.launchFailed(error.localizedDescription)
        }

        if let standardInput {
            // 写入后立刻关闭，避免子进程等待 EOF 而挂住。
            inPipe.fileHandleForWriting.write(Data(standardInput.utf8))
            try? inPipe.fileHandleForWriting.close()
        }

        let outHandle = outPipe.fileHandleForReading
        let errHandle = errPipe.fileHandleForReading

        let outTask = Task.detached(priority: .userInitiated) {
            outHandle.readDataToEndOfFile()
        }
        let errTask = Task.detached(priority: .userInitiated) {
            errHandle.readDataToEndOfFile()
        }

        // 使用单调时钟，避免系统时间跳变影响超时判定。
        let deadline = ContinuousClock.now + .seconds(timeoutSeconds)
        while process.isRunning {
            if ContinuousClock.now >= deadline {
                await terminate(process)
                // 即使强制终止，pipe 写端仍可能被孙进程持有；读取必须有界。
                let readDeadline = ContinuousClock.now + .milliseconds(1500)
                _ = await boundedValue(of: outTask, timeout: readDeadline - ContinuousClock.now)
                _ = await boundedValue(of: errTask, timeout: readDeadline - ContinuousClock.now)
                throw ProcessRunnerError.timedOut
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        // 直接子进程已退出，但孙进程可能仍持有 pipe 写端，EOF 不保证到来。
        guard let outData = await boundedValue(of: outTask, timeout: deadline - ContinuousClock.now) else {
            throw ProcessRunnerError.timedOut
        }
        guard let errData = await boundedValue(of: errTask, timeout: deadline - ContinuousClock.now) else {
            throw ProcessRunnerError.timedOut
        }

        return Result(
            status: process.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self)
        )
    }

    /// 先发 SIGTERM，给 1.5 秒宽限期；仍存活则升级为 SIGKILL。
    private static func terminate(_ process: Process) async {
        process.terminate()

        let graceDeadline = ContinuousClock.now + .milliseconds(1500)
        while process.isRunning && ContinuousClock.now < graceDeadline {
            try? await Task.sleep(for: .milliseconds(50))
        }

        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }

    /// 在给定时间内等待任务结果；超时返回 nil。continuation 只会被恢复一次。
    private static func boundedValue<T: Sendable>(
        of task: Task<T, Never>,
        timeout: Duration
    ) async -> T? {
        guard timeout > .zero else { return nil }

        let gate = ResumeGate()
        return await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
            Task {
                let value = await task.value
                if await gate.claim() {
                    continuation.resume(returning: value)
                }
            }
            Task {
                try? await Task.sleep(for: timeout)
                if await gate.claim() {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
