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

    public static func run(
        _ executable: String,
        _ arguments: [String],
        timeoutSeconds: Double = 60
    ) async throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            throw ProcessRunnerError.launchFailed(error.localizedDescription)
        }

        let outHandle = outPipe.fileHandleForReading
        let errHandle = errPipe.fileHandleForReading

        let outTask = Task.detached(priority: .userInitiated) {
            outHandle.readDataToEndOfFile()
        }
        let errTask = Task.detached(priority: .userInitiated) {
            errHandle.readDataToEndOfFile()
        }

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while process.isRunning {
            if Date() >= deadline {
                process.terminate()
                _ = await outTask.value
                _ = await errTask.value
                throw ProcessRunnerError.timedOut
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        let outData = await outTask.value
        let errData = await errTask.value

        return Result(
            status: process.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self)
        )
    }
}
