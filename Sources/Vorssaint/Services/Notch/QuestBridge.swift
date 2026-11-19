// SPDX-License-Identifier: GPL-3.0-or-later
// QuestBridge – lokaler Patch (Branch quest-bridge), nicht Teil von upstream.
//
// Hängt jedes Ereignis des Notch-Timers als eine JSON-Zeile an
//   ~/Library/Application Support/QuestBridge/timer-events.jsonl
// an, z. B.
//   {"id":"…","event":"start","mode":"pomodoro","phase":"focus","minutes":25,"at":"2026-11-19T13:45:00.000Z"}
//
// Vorssaint spricht mit niemandem; die Task-Manager-App liest die Datei.
// Ereignisse: start, pause, resume, next, cancel, finish.
// Bewusst eine eigenständige Datei mit Einzeiler-Hooks in NotchTimerService,
// damit sich der Patch leicht auf upstream rebasen lässt.

import Foundation

enum QuestBridge {
    enum Event: String { case start, pause, resume, next, cancel, finish }

    /// Schreiben läuft seriell im Hintergrund – der Timer wartet nie auf die Platte.
    private static let queue = DispatchQueue(label: "QuestBridge", qos: .utility)

    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/QuestBridge", isDirectory: true)
            .appendingPathComponent("timer-events.jsonl")
    }

    /// Protokolliert ein Ereignis mit dem Zustand der Sitzung danach.
    /// `cancel` wird VOR dem Zurücksetzen aufgerufen; ohne Sitzung passiert nichts.
    static func record(_ event: Event, _ session: NotchTimerSession) {
        guard session.hasSession else { return }
        let line: [String: Any] = [
            "id": UUID().uuidString.lowercased(),
            "event": event.rawValue,
            "mode": session.mode.rawValue,
            "phase": session.phase.rawValue,
            "minutes": session.countsUp ? NSNull() : Int((session.duration / 60).rounded()) as Any,
            "at": timestamp(Date()),
        ]
        append(line)
    }

    /// Für pauseOrResume: erkennt am Zustand danach, was passiert ist.
    static func recordToggle(_ session: NotchTimerSession) {
        if session.isPaused { record(.pause, session) }
        else if session.isRunning { record(.resume, session) }
        else if session.completed { record(.finish, session) }  // Pause genau am Ende
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func append(_ object: [String: Any]) {
        queue.async {
            guard var data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            else { return }
            data.append(0x0A)  // "\n"
            let url = fileURL
            do {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                if !FileManager.default.fileExists(atPath: url.path) {
                    FileManager.default.createFile(atPath: url.path, contents: nil,
                                                   attributes: [.posixPermissions: 0o600])
                }
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } catch {
                // Die Bridge darf Vorssaint nie stören – Fehler werden ignoriert.
            }
        }
    }
}
