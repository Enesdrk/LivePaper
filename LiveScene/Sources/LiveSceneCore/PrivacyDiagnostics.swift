import Foundation

public enum PrivacyDiagnostics {
    public static func errorSummary(_ error: Error, privacyModeEnabled: Bool) -> String {
        if privacyModeEnabled {
            return String(describing: type(of: error))
        }
        return error.localizedDescription
    }

    public static func pathForDisplay(_ path: String, privacyModeEnabled: Bool) -> String {
        if privacyModeEnabled {
            return (path as NSString).lastPathComponent
        }
        return path
    }

    public static func log(
        _ subsystem: String,
        _ message: String,
        error: Error? = nil,
        privacyModeEnabled: Bool = true
    ) {
        if let error {
            NSLog("[\(subsystem)] \(message): \(errorSummary(error, privacyModeEnabled: privacyModeEnabled))")
            return
        }
        NSLog("[\(subsystem)] \(message)")
    }
}
