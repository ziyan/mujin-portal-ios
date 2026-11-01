import Foundation
import PortalKit

/// CameraFiles downloads clips of the recording to the device's temporary
/// folder. A clip can be tens of megabytes, so it goes to a file instead of
/// being held in memory.
enum CameraFiles {
    struct Download {
        let url: URL
        /// Where the NVR actually started, which is at the key frame before the moment asked for. Nil when it did not say.
        let actualStartMS: Double?
    }

    static func download(path: String, connection: Connection, isDemo: Bool, startMS: Double) async throws -> Download {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("camera-clips", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent("clip-\(UUID().uuidString).mp4")
        if isDemo {
            guard let source = Bundle.main.url(forResource: "DemoCamera", withExtension: "mp4") else { throw PortalError.refused("HTTP 404") }
            try FileManager.default.copyItem(at: source, to: destination)
            return Download(url: destination, actualStartMS: startMS)
        }
        let token = try await connection.accessToken()
        let server = await connection.server
        var request = URLRequest(url: server.endpoint(path))
        request.timeoutInterval = 120
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (temporary, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            try? FileManager.default.removeItem(at: temporary)
            throw PortalError.refused("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
        let actualStart = http.value(forHTTPHeaderField: "x-start-timestamp").flatMap(Double.init)
        return Download(url: destination, actualStartMS: actualStart)
    }

    /// A name for a shared clip that says which camera and which moment, in the NVR's clock.
    static func fileName(cameraName: String, startMS: Double, clock: CameraClock) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = clock.timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date(timeIntervalSince1970: startMS / 1000))
        let stamp = String(format: "%04d-%02d-%02d_%02d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
        let safeName = cameraName.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" }
        return "\(String(safeName))_\(stamp).mp4"
    }
}
