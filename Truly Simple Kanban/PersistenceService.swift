import Foundation

class PersistenceService {
    static let shared = PersistenceService()
    
    private let tasksFilename = "kanbanTasks.json"
    private let hasLaunchedBeforeKey = "appHasLaunchedBefore"

    private var tasksFileURL: URL {
        do {
            let documentsDirectory = try FileManager.default.url(for: .documentDirectory,
                                                               in: .userDomainMask,
                                                               appropriateFor: nil,
                                                               create: false)
            return documentsDirectory.appendingPathComponent(tasksFilename)
        } catch {
            fatalError("Could not construct documents directory URL: \(error)")
        }
    }

    private init() {}

    func loadTasks() -> [Task] {
        let userDefaults = UserDefaults.standard
        let hasLaunchedBefore = userDefaults.bool(forKey: hasLaunchedBeforeKey)

        if !hasLaunchedBefore {
            userDefaults.set(true, forKey: hasLaunchedBeforeKey)
            print("First launch detected. Returning default tasks.")
            return getDefaultTasks()
        }
        
        // On subsequent launches, load from disk.
        guard FileManager.default.fileExists(atPath: tasksFileURL.path) else {
            print("Tasks file not found on subsequent launch. Returning empty array.")
            return []
        }

        do {
            let data = try Data(contentsOf: tasksFileURL)
            let decoder = JSONDecoder()
            let decodedTasks = try decoder.decode([Task].self, from: data)
            print("Tasks loaded successfully from: \(tasksFileURL)")

            // --- Migration logic to ensure orderIndex is consistent ---
            var finalTasks: [Task] = []
            for status in TaskStatus.allCases {
                var statusTasks = decodedTasks.filter { $0.status == status }
                let needsMigration = statusTasks.contains { $0.orderIndex == 0.0 } && statusTasks.count > 1
                
                if needsMigration {
                    for i in 0..<statusTasks.count {
                        statusTasks[i].orderIndex = Double(i)
                    }
                }
                finalTasks.append(contentsOf: statusTasks)
            }
            
            // Return the loaded tasks, even if the array is empty.
            return finalTasks
            
        } catch {
            print("Could not load or decode tasks: \(error.localizedDescription). Returning empty array as a fallback.")
            // Return an empty array on error to prevent data loss.
            return []
        }
    }

    func saveTasks(_ tasks: [Task]) {
        let fileManager = FileManager.default
        let directoryURL = tasksFileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directoryURL.path) {
            do {
                try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
                print("Created documents directory at: \(directoryURL.path)")
            } catch {
                print("Could not create documents directory for saving: \(error.localizedDescription)")
                return
            }
        }
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(tasks)
            try data.write(to: tasksFileURL, options: [.atomicWrite])
            print("Tasks saved successfully to: \(tasksFileURL.path)")
        } catch {
            print("Could not save tasks: \(error.localizedDescription)")
        }
    }
    
    private func getDefaultTasks() -> [Task] {
        return [
            Task(title: "Tap the plus sign to add a task", description: "Tap a task to edit it", status: .todo, orderIndex: 0.0),
            Task(title: "Long-tap a task to delete or drag it to a new position", description: "Within the same row, or in a different one", status: .inProgress, orderIndex: 0.0),
            Task(title: "Everything is saved on your device", status: .inProgress, orderIndex: 1.0),
            Task(title: "I hope you enjoy Truly Simple Kanban :)", status: .done, orderIndex: 0.0)
        ]
    }
}
