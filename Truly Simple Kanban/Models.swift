// Models.swift (or at the top of your ContentView.swift)
import Foundation
import SwiftUI

enum TaskStatus: String, CaseIterable, Identifiable, Codable {
    case todo = "To Do"
    case inProgress = "In Progress"
    case done = "Done"

    var id: String { self.rawValue }

    // Updated for a minimalist look
    var accentColor: Color {
        return Color.primary.opacity(0.7) // A standard, slightly less prominent text color
    }
}

struct Task: Identifiable, Equatable, Codable {
    let id: UUID
    var title: String
    var description: String?
    var status: TaskStatus
    var orderIndex: Double // New property for ordering within a column

    init(id: UUID = UUID(), title: String, description: String? = nil, status: TaskStatus = .todo, orderIndex: Double = 0.0) {
        self.id = id
        self.title = title
        self.description = description
        self.status = status
        self.orderIndex = orderIndex
    }
}
