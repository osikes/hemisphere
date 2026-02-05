import Foundation

func log(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let logMessage = "[\(timestamp)] \(message)\n"
    let logPath = FileManager.default.homeDirectoryForCurrentUser.path + "/hemisphere.log"
    if let handle = FileHandle(forWritingAtPath: logPath) {
        handle.seekToEndOfFile()
        handle.write(logMessage.data(using: .utf8)!)
        handle.closeFile()
    } else {
        FileManager.default.createFile(atPath: logPath, contents: logMessage.data(using: .utf8), attributes: nil)
    }
}
