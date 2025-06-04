// PersistenceService.swift
import Foundation

class PersistenceService {
    static let shared = PersistenceService() // Singleton
    private let tasksFilename = "kanbanTasks.json"

    private var tasksFileURL: URL {
        do {
            let documentsDirectory = try FileManager.default.url(for: .documentDirectory,
                                                               in: .userDomainMask,
                                                               appropriateFor: nil,
                                                               create: false) // create: false, as we only need it if it exists for reading
            return documentsDirectory.appendingPathComponent(tasksFilename)
        } catch {
            // This path should ideally not fail unless there's a serious OS issue.
            fatalError("Could not construct documents directory URL: \(error)")
        }
    }

    private init() {} // Private initializer for singleton

    func loadTasks() -> [Task] {
        // Ensure the directory exists before trying to read or write.
        // This isn't strictly necessary for reading (it would just fail),
        // but good for consistency if we were creating the directory.
        let fileManager = FileManager.default
        let documentsDirectoryPath = tasksFileURL.deletingLastPathComponent().path
        if !fileManager.fileExists(atPath: documentsDirectoryPath) {
            do {
                try fileManager.createDirectory(atPath: documentsDirectoryPath, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("Could not create documents directory: \(error). Proceeding without.")
                // If directory creation fails, loading will also likely fail, and defaults will be returned.
            }
        }
        
        guard fileManager.fileExists(atPath: tasksFileURL.path) else {
            print("Tasks file does not exist at \(tasksFileURL.path). Returning default tasks.")
            return getDefaultTasks()
        }

        do {
            let data = try Data(contentsOf: tasksFileURL)
            let decoder = JSONDecoder()
            let decodedTasks = try decoder.decode([Task].self, from: data)
            print("Tasks loaded successfully from: \(tasksFileURL)")

            // --- Optional: Migration for tasks missing orderIndex ---
            var migratedTasks: [Task] = []
            // Group tasks by status to assign orderIndex correctly within each column
            let tasksGroupedByStatus = Dictionary(grouping: decodedTasks, by: { $0.status })
            
            for status in TaskStatus.allCases {
                if let tasksInStatus = tasksGroupedByStatus[status] {
                    var orderCounter: Double = 0.0
                    for var task in tasksInStatus {
                        // A simple check: if orderIndex is the default (0.0) and it's not the only task with 0.0 in its status group,
                        // it likely needs migration or was genuinely the first.
                        // A more robust check might be to see if the `orderIndex` key was present during decoding.
                        // For now, we assume if it's 0.0 and there are others at 0.0, it might be uninitialized.
                        // Or, more simply, re-assign orderIndex if it looks like default values.
                        // A safer approach if you're unsure is to always re-index on first load after adding the field.
                        // This is a basic heuristic: if it's 0.0, assign a new sequential one.
                        // This logic might be too aggressive if 0.0 is a valid user-set order.
                        // A better check would be if `task.orderIndex` was nil if it were optional,
                        // or to check if the raw JSON for that task had the key.
                        // For this example, let's assume tasks from old versions will have 0.0
                        // and we want to re-sequence them.
                        
                        // If the task's orderIndex is still its default AND we want to ensure uniqueness,
                        // or if we suspect it's from an older version:
                        if task.orderIndex == 0.0 { // This condition might need refinement based on how `orderIndex` was used before.
                                                   // If all old tasks have 0.0, this will re-index them.
                            task.orderIndex = orderCounter
                            orderCounter += 1.0
                        }
                        // If we want to ensure all tasks in a status group have unique, sequential orderIndexes
                        // after loading, irrespective of their current orderIndex:
                        // task.orderIndex = orderCounter
                        // orderCounter += 1.0

                        migratedTasks.append(task)
                    }
                }
            }
            // We need to re-sort `migratedTasks` to match the original overall order
            // if the grouping and re-iteration changed it, or just ensure the final output is sorted as expected.
            // However, `ContentView` will sort by status and then by `orderIndex` anyway.
            // The primary goal here is that tasks within the same status have distinct and sequential `orderIndex`.
            
            // A simpler migration: if ANY task has the default 0.0, re-index ALL tasks for that status.
            var finalTasks: [Task] = []
            for status in TaskStatus.allCases {
                var statusTasks = decodedTasks.filter { $0.status == status }
                // Check if any task in this status group needs migration (e.g., has default orderIndex)
                // This assumes 0.0 is only a default and not a user-intended value if multiple tasks have it.
                let needsMigration = statusTasks.contains { $0.orderIndex == 0.0 } && statusTasks.count > 1
                
                if needsMigration {
                    for i in 0..<statusTasks.count {
                        statusTasks[i].orderIndex = Double(i)
                    }
                }
                finalTasks.append(contentsOf: statusTasks)
            }
             return finalTasks.isEmpty ? getDefaultTasks() : finalTasks // Return migrated or original if no migration needed
            // return decodedTasks // If no migration logic is applied
            
        } catch {
            print("Could not load tasks: \(error.localizedDescription). Error: \(error). Returning default tasks.")
            return getDefaultTasks()
        }
    }

    func saveTasks(_ tasks: [Task]) {
        // Ensure the directory exists before writing.
        let fileManager = FileManager.default
        let directoryURL = tasksFileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directoryURL.path) {
            do {
                try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
                print("Created documents directory at: \(directoryURL.path)")
            } catch {
                print("Could not create documents directory for saving: \(error.localizedDescription)")
                return // Cannot save if directory can't be created
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

    // Helper to provide some default tasks if loading fails or on first launch
    private func getDefaultTasks() -> [Task] {
        return [
            Task(title: "Design UI Mockups", description: "Create mockups in Figma", status: .todo, orderIndex: 0.0),
            Task(title: "Develop API Endpoints", description: "For user authentication", status: .inProgress, orderIndex: 0.0),
            Task(title: "Write Unit Tests", status: .inProgress, orderIndex: 1.0),
            Task(title: "Deploy to TestFlight", status: .done, orderIndex: 0.0)
        ]
    }
}
