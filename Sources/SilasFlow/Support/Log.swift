import Foundation
import os

/// Central logger. View live with:
///   log stream --predicate 'subsystem == "com.silasflow.app"' --level debug
enum Log {
    static let app = Logger(subsystem: "com.silasflow.app", category: "app")
    static let audio = Logger(subsystem: "com.silasflow.app", category: "audio")
    static let stt = Logger(subsystem: "com.silasflow.app", category: "stt")
    static let cleanup = Logger(subsystem: "com.silasflow.app", category: "cleanup")
    static let inject = Logger(subsystem: "com.silasflow.app", category: "inject")
}
