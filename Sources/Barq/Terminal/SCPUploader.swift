import Foundation

/// Runs an SCP upload for a dropped file. Arg building is delegated to the
/// tested SSHCommandBuilder; this just spawns the process.
enum SCPUploader {
    /// Upload `localPath` to `remoteDir` on the profile's host.
    static func upload(localPath: String, remoteDir: String, profile: ConnectionProfile, completion: @escaping (Bool, String) -> Void) {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: localPath, isDirectory: &isDir)
        let fileName = (localPath as NSString).lastPathComponent
        let dest = remoteDir.hasSuffix("/") ? remoteDir + fileName : remoteDir + "/" + fileName
        let args = SSHCommandBuilder.scpArguments(
            for: profile, localPath: localPath, remotePath: dest, upload: true, recursive: isDir.boolValue
        )
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/scp")
        process.arguments = args
        let err = Pipe()
        process.standardError = err
        process.terminationHandler = { proc in
            let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                completion(proc.terminationStatus == 0, stderr)
            }
        }
        do {
            try process.run()
        } catch {
            completion(false, error.localizedDescription)
        }
    }
}
