// TrulySimpleKanbanApp.swift
import SwiftUI

@main
struct TrulySimpleKanbanApp: App {
    // let persistenceController = PersistenceController.shared // REMOVE if not used

    var body: some Scene {
        WindowGroup {
            ContentView()
                // .environment(\.managedObjectContext, persistenceController.container.viewContext) // REMOVE
        }
    }
}
