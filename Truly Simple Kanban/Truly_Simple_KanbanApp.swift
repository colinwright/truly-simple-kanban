//
//  Truly_Simple_KanbanApp.swift
//  Truly Simple Kanban
//
//  Created by Colin Wright on 6/4/25.
//

import SwiftUI

@main
struct Truly_Simple_KanbanApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
