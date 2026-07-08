import Foundation

/// Appends human-readable diagnostics to ~/Library/Logs/SilasFlow.log
/// (and stderr), so the pipeline can be traced even when the app is
/// launched from Finder. Tail it with:
///   tail -f ~/Library/Logs/SilasFlow.log
enum Diag {
    static let logURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("SilasFlow.log")
    }()

    private static let queue = DispatchQueue(label: "com.silasflow.diag")

    static func log(_ message: String) {
        let line = "[\(timestamp())] \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))
        queue.async {
            if let data = line.data(using: .utf8) {
                if let handle = try? FileHandle(forWritingTo: logURL) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.close()
                } else {
                    try? data.write(to: logURL)
                }
            }
        }
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: Date())
    }
}
