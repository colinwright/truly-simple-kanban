// ContentView.swift
import UniformTypeIdentifiers
import SwiftUI
import os

// Struct to describe a drop target for visual feedback
struct DropTargetInfo: Equatable {
    var taskID: UUID?
    var columnStatus: TaskStatus
}

// MARK: - Main Kanban Board View
struct KanbanBoardView: View {
    @Binding var tasks: [Task]
    @Binding var showingAddTaskSheet: Bool
    @Binding var taskToEdit: Task?

    @Binding var activeDragID: UUID?
    @Binding var dropTargetInfo: DropTargetInfo?
    @Binding var recentlyDroppedTaskID: UUID?

    let filteredTasksClosure: (TaskStatus) -> [Task]
    let deleteTaskClosure: (Task) -> Void
    let saveTasksClosure: ([Task]) -> Void
    let appendNewTaskClosure: (String, String) -> Void
    let updateTaskClosure: (UUID, String, String, TaskStatus) -> Void
    let handleDropClosure: (_ sourceTaskID: UUID, _ targetColumn: TaskStatus, _ insertBeforeTaskID: UUID?) -> Void

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 20) {
                    ForEach(TaskStatus.allCases) { status in
                        KanbanColumnView(
                            status: status,
                            tasks: filteredTasksClosure(status),
                            activeDragID: $activeDragID,
                            dropTargetInfo: $dropTargetInfo,
                            recentlyDroppedTaskID: $recentlyDroppedTaskID,
                            onEditTask: { task in self.taskToEdit = task },
                            onDeleteTask: deleteTaskClosure,
                            handleDrop: handleDropClosure
                        )
                    }
                }
                .padding()
            }
            .frame(height: geometry.size.height)
        }
        .background(Color.appBackground.edgesIgnoringSafeArea(.all))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showingAddTaskSheet = true } label: { Image(systemName: "plus.circle.fill").font(.title2).foregroundColor(Color.primaryText) }
            }
            ToolbarItem(placement: .principal) { Text("Truly Simple Kanban").font(.system(size: 12, weight: .medium)).foregroundColor(Color.secondaryText) }
        }
        .toolbarBackground(Color.appBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .sheet(isPresented: $showingAddTaskSheet) {
            AddTaskView { title, description in
                self.appendNewTaskClosure(title, description)
            }
        }
        .sheet(item: $taskToEdit) { taskToActuallyEdit in
            EditTaskView(
                task: taskToActuallyEdit,
                onSave: { id, newTitle, newDescription, newStatus in self.updateTaskClosure(id, newTitle, newDescription, newStatus); self.taskToEdit = nil },
                onDelete: { taskIdToDelete in
                    if let taskToDeleteObject = tasks.first(where: { $0.id == taskIdToDelete }) { self.deleteTaskClosure(taskToDeleteObject) }
                    self.taskToEdit = nil
                }
            )
        }
        .onChange(of: tasks, perform: saveTasksClosure)
        .onChange(of: activeDragID) { newValue in
            if newValue == nil { // Drag ended or was cancelled
                if dropTargetInfo != nil {
                    dropTargetInfo = nil
                }
            }
        }
    }
}

// MARK: - Main Content View (Root View of the App)
struct ContentView: View {
    @State private var tasks: [Task] = PersistenceService.shared.loadTasks()
    @State private var showingAddTaskSheet = false
    @State private var taskToEdit: Task?

    @State private var activeDragID: UUID? = nil
    @State private var dropTargetInfo: DropTargetInfo? = nil
    @State private var recentlyDroppedTaskID: UUID? = nil

    init() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Color.appBackground)
        let titleFont = UIFont.systemFont(ofSize: 12, weight: .medium)
        appearance.titleTextAttributes = [.foregroundColor: UIColor(Color.secondaryText), .font: titleFont]
        appearance.shadowColor = .clear
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
    }

    var body: some View {
        NavigationView {
            KanbanBoardView(
                tasks: $tasks,
                showingAddTaskSheet: $showingAddTaskSheet,
                taskToEdit: $taskToEdit,
                activeDragID: $activeDragID,
                dropTargetInfo: $dropTargetInfo,
                recentlyDroppedTaskID: $recentlyDroppedTaskID,
                filteredTasksClosure: self.filteredTasks,
                deleteTaskClosure: self.deleteTask,
                saveTasksClosure: PersistenceService.shared.saveTasks,
                appendNewTaskClosure: self.appendNewTask,
                updateTaskClosure: self.updateTask,
                handleDropClosure: self.handleDropOperation
            )
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .accentColor(Color.primaryText)
    }

    private func filteredTasks(for status: TaskStatus) -> [Task] {
        tasks.filter { $0.status == status }.sorted { $0.orderIndex < $1.orderIndex }
    }

    private func deleteTask(_ taskToDelete: Task) {
        if activeDragID == taskToDelete.id {
            activeDragID = nil
            NSLog("[DeleteTask] Cleared activeDragID for deleted task: %@", taskToDelete.id.uuidString)
        }
        if recentlyDroppedTaskID == taskToDelete.id {
            recentlyDroppedTaskID = nil
            NSLog("[DeleteTask] Cleared recentlyDroppedTaskID for deleted task: %@", taskToDelete.id.uuidString)
        }
        
        let status = taskToDelete.status
        tasks.removeAll { $0.id == taskToDelete.id }
        reindexTasks(inColumn: status)
    }

    private func appendNewTask(title: String, description: String) {
        let todos = tasks.filter { $0.status == .todo }
        let nextIdx = (todos.map { $0.orderIndex }.max() ?? -1.0) + 1.0
        tasks.append(Task(title: title, description: description.isEmpty ? nil : description, status: .todo, orderIndex: nextIdx))
    }

    private func updateTask(id: UUID, newTitle: String, newDescription: String, newStatus: TaskStatus) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        let oldStatus = tasks[idx].status
        tasks[idx].title = newTitle
        tasks[idx].description = newDescription.isEmpty ? nil : newDescription
        if oldStatus != newStatus {
            tasks[idx].status = newStatus
            let newColTasks = tasks.filter { $0.status == newStatus && $0.id != id }
            tasks[idx].orderIndex = (newColTasks.map { $0.orderIndex }.max() ?? -1.0) + 1.0
            reindexTasks(inColumn: oldStatus)
            reindexTasks(inColumn: newStatus)
        }
    }
    
    private func handleDropOperation(sourceTaskID: UUID, targetColumn: TaskStatus, insertBeforeTaskID: UUID?) {
        guard let sourceTaskIndex = tasks.firstIndex(where: { $0.id == sourceTaskID }) else {
            NSLog("Error: Source task for drop not found (ID: %@)", sourceTaskID.uuidString)
            activeDragID = nil
            return
        }
        
        var taskToMove = tasks.remove(at: sourceTaskIndex)
        let oldStatus = taskToMove.status
        
        taskToMove.status = targetColumn
        
        if let beforeID = insertBeforeTaskID {
            if let beforeTask = tasks.first(where: { $0.id == beforeID && $0.status == targetColumn }) {
                taskToMove.orderIndex = beforeTask.orderIndex - 0.5
            } else {
                let maxOrder = tasks.filter { $0.status == targetColumn }.map { $0.orderIndex }.max() ?? -1.0
                taskToMove.orderIndex = maxOrder + 1.0
            }
        } else {
            let maxOrder = tasks.filter { $0.status == targetColumn }.map { $0.orderIndex }.max() ?? -1.0
            taskToMove.orderIndex = maxOrder + 1.0
        }
        
        tasks.append(taskToMove)
        NSLog("Moved task '%@' from %@ to %@. Target orderIndex (pre-reindex): %.2f", taskToMove.title, oldStatus.rawValue, targetColumn.rawValue, taskToMove.orderIndex)

        if oldStatus != targetColumn { reindexTasks(inColumn: oldStatus) }
        reindexTasks(inColumn: targetColumn)
    }

    private func reindexTasks(inColumn status: TaskStatus) {
        var columnTasks = tasks.filter { $0.status == status }
        columnTasks.sort { $0.orderIndex < $1.orderIndex }

        for (newIndex, taskInColumn) in columnTasks.enumerated() {
            if let masterTaskIndex = tasks.firstIndex(where: { $0.id == taskInColumn.id }) {
                if tasks[masterTaskIndex].orderIndex != Double(newIndex) {
                    tasks[masterTaskIndex].orderIndex = Double(newIndex)
                }
            }
        }
        NSLog("[Reindex] Column: %@ re-indexed. Task count: %d", status.rawValue, columnTasks.count)
    }
}

// MARK: - Kanban Column View
struct KanbanColumnView: View {
    let status: TaskStatus
    let tasks: [Task]
    @Binding var activeDragID: UUID?
    @Binding var dropTargetInfo: DropTargetInfo?
    @Binding var recentlyDroppedTaskID: UUID?
    var onEditTask: (Task) -> Void
    var onDeleteTask: (Task) -> Void
    let handleDrop: (_ sourceTaskID: UUID, _ targetColumn: TaskStatus, _ insertBeforeTaskID: UUID?) -> Void

    var body: some View {
        let isColumnHighlightedForEndDrop = dropTargetInfo?.columnStatus == status && dropTargetInfo?.taskID == nil && activeDragID != nil
        
        VStack(alignment: .leading, spacing: 12) {
            Text(status.rawValue.uppercased())
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .kerning(0.5)
                .padding([.horizontal, .bottom], 8)
                .foregroundColor(status.accentColor)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .center, spacing: 0) {
                    ForEach(tasks) { task in
                        TaskSlotView(
                            task: task,
                            columnStatus: status,
                            activeDragID: $activeDragID,
                            dropTargetInfo: $dropTargetInfo,
                            recentlyDroppedTaskID: $recentlyDroppedTaskID,
                            onEditTask: onEditTask,
                            onDeleteTask: onDeleteTask,
                            handleDrop: handleDrop
                        )
                        .id(task.id)
                    }
                    EndColumnDropArea(status: status, isTargeted: isColumnHighlightedForEndDrop, tasksInColumn: tasks.count)
                        .dropDestination(for: String.self) { items, location in
                            guard let draggedItemIDString = items.first,
                                  let currentDraggedTaskID = UUID(uuidString: draggedItemIDString),
                                  self.activeDragID == currentDraggedTaskID else {
                                NSLog("[EndColumnDropArea] Drop rejected: No active drag or item mismatch.")
                                return false
                            }
                            
                            NSLog("[EndColumnDropArea '%@'] ACTION: Dropping ID '%@'", self.status.rawValue, currentDraggedTaskID.uuidString)
                            
                            let droppedID = currentDraggedTaskID
                            self.activeDragID = nil
                            self.recentlyDroppedTaskID = droppedID

                            handleDrop(droppedID, self.status, nil)
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                if self.recentlyDroppedTaskID == droppedID {
                                    self.recentlyDroppedTaskID = nil
                                }
                            }
                            return true
                        } isTargeted: { isTargetedValue in
                            let currentTargetForThisZone = DropTargetInfo(taskID: nil, columnStatus: self.status)
                            if isTargetedValue && self.activeDragID != nil {
                                if self.dropTargetInfo != currentTargetForThisZone {
                                    self.dropTargetInfo = currentTargetForThisZone
                                }
                            } else {
                                if self.dropTargetInfo == currentTargetForThisZone {
                                    self.dropTargetInfo = nil
                                }
                            }
                        }
                        .id("columnEndSpacer-\(status.id)")
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(12)
        .frame(width: 300)
        .frame(maxHeight: .infinity)
        .background(Color.columnBackground)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.subtleBorder, lineWidth: 0.75))
    }
}

// MARK: - Styled End of Column Drop Area
struct EndColumnDropArea: View {
    let status: TaskStatus
    let isTargeted: Bool
    let tasksInColumn: Int

    var body: some View {
        VStack {
            Image(systemName: "chevron.down.circle")
                .font(.title2)
                .foregroundColor(isTargeted ? Color.accentColor : Color.secondaryText.opacity(0.5))
            Text("Move to bottom of \(status.rawValue)")
                .font(.caption)
                .foregroundColor(isTargeted ? Color.accentColor : Color.secondaryText.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        // Removed idealHeight to prevent conflict with minHeight.
        // Adjusted minHeight values slightly for balance.
        .frame(minHeight: tasksInColumn == 0 ? 180 : 70)
        .background(isTargeted ? Color.accentColor.opacity(0.15) : Color.clear)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isTargeted ? Color.accentColor : Color.subtleBorder.opacity(0.5),
                        style: StrokeStyle(lineWidth: isTargeted ? 1.5 : 1, dash: [isTargeted ? 0 : 4]))
        )
        .padding(.top, tasksInColumn == 0 ? 0 : 8)
        // Consistent bottom padding logic: add if empty, otherwise rely on parent spacing.
        .padding(.bottom, tasksInColumn == 0 ? 8 : 0)
        .contentShape(Rectangle())
    }
}


// MARK: - Task Slot View
struct TaskSlotView: View {
    let task: Task
    let columnStatus: TaskStatus
    @Binding var activeDragID: UUID?
    @Binding var dropTargetInfo: DropTargetInfo?
    @Binding var recentlyDroppedTaskID: UUID?
    var onEditTask: (Task) -> Void
    var onDeleteTask: (Task) -> Void
    let handleDrop: (_ sourceTaskID: UUID, _ targetColumn: TaskStatus, _ insertBeforeTaskID: UUID?) -> Void

    var body: some View {
        let isBeingDragged = activeDragID == task.id
        let showPlaceholder = dropTargetInfo?.taskID == task.id && dropTargetInfo?.columnStatus == columnStatus && activeDragID != nil && activeDragID != task.id
        
        VStack(spacing: 0) {
            if showPlaceholder {
                DropPlaceholderView().padding(.bottom, 4)
            }
            TaskCardView(task: task, onTap: { onEditTask(task) }, isBeingDragged: isBeingDragged)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onDrag {
            if self.recentlyDroppedTaskID == task.id {
                NSLog("[TaskSlot '%@'] onDrag: BLOCKED (recently dropped cooldown).", task.title)
                if self.activeDragID == task.id {
                    NSLog("[TaskSlot '%@'] onDrag: Clearing stuck activeDragID as task is on cooldown.", task.title)
                    self.activeDragID = nil
                }
                return NSItemProvider()
            }

            if let currentActiveDrag = self.activeDragID, currentActiveDrag != task.id {
                NSLog("[TaskSlot '%@'] onDrag: activeDragID (%@) belonged to a different task. Resetting it.", task.title, currentActiveDrag.uuidString)
                self.activeDragID = nil
            }
            
            if self.activeDragID != task.id {
                NSLog("[TaskSlot '%@'] onDrag: INITIATING DRAG. Setting activeDragID.", task.title)
                self.activeDragID = task.id
            } else {
                NSLog("[TaskSlot '%@'] onDrag: CONTINUING DRAG.", task.title)
            }

            if let recentDrop = self.recentlyDroppedTaskID, recentDrop != task.id {
                NSLog("[TaskSlot '%@'] onDrag: Clearing stale recentlyDroppedTaskID (%@) for other task.", task.title, recentDrop.uuidString)
                self.recentlyDroppedTaskID = nil
            }
            
            NSLog("[TaskSlot '%@'] onDrag: PROVIDING ITEM. Active: %@, RecentlyDropped: %@",
                  task.title, self.activeDragID?.uuidString ?? "nil", self.recentlyDroppedTaskID?.uuidString ?? "nil")
            return NSItemProvider(object: task.id.uuidString as NSString)
        }
        .dropDestination(for: String.self) { items, location in
            guard let draggedItemIDString = items.first,
                  let currentDraggedTaskID = UUID(uuidString: draggedItemIDString),
                  self.activeDragID == currentDraggedTaskID else {
                NSLog("[TaskSlotDrop] Drop rejected: No active drag or item mismatch.")
                return false
            }
            guard currentDraggedTaskID != task.id else {
                NSLog("[TaskSlotDrop] Drop rejected: Cannot drop task on itself.")
                self.activeDragID = nil
                self.dropTargetInfo = nil
                return false
            }
            
            NSLog("[TaskSlotDrop '%@'] ACTION: Dropping ID '%@' before this task.", task.title, currentDraggedTaskID.uuidString)
            
            let droppedID = currentDraggedTaskID
            self.activeDragID = nil
            self.recentlyDroppedTaskID = droppedID

            handleDrop(droppedID, self.columnStatus, self.task.id)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if self.recentlyDroppedTaskID == droppedID {
                     self.recentlyDroppedTaskID = nil
                }
            }
            return true
        } isTargeted: { isTargetedValue in
            let currentTargetForThisZone = DropTargetInfo(taskID: task.id, columnStatus: self.columnStatus)
            if isTargetedValue && self.activeDragID != nil && self.activeDragID != task.id {
                if self.dropTargetInfo != currentTargetForThisZone {
                     self.dropTargetInfo = currentTargetForThisZone
                }
            } else {
                if self.dropTargetInfo == currentTargetForThisZone {
                    self.dropTargetInfo = nil
                }
            }
        }
        .contextMenu { Button(role: .destructive) { onDeleteTask(task) } label: { Label("Delete Task", systemImage: "trash") } }
    }
}

// MARK: - Task Card View (Visuals only)
struct TaskCardView: View {
    let task: Task
    var onTap: (() -> Void)? = nil
    var isBeingDragged: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(task.title).font(.system(size: 15, weight: .medium, design: .rounded)).foregroundColor(Color.primaryText).lineLimit(3)
            if let description = task.description, !description.isEmpty {
                Text(description).font(.system(size: 13, design: .rounded)).foregroundColor(Color.secondaryText).lineLimit(2).padding(.top, 2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cardBackground)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.subtleBorder.opacity(0.6), lineWidth: 0.75))
        .opacity(isBeingDragged ? 0.4 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isBeingDragged)
        .onTapGesture { onTap?() }
    }
}

// MARK: - Drop Placeholder View
struct DropPlaceholderView: View {
    var body: some View {
        Rectangle()
            .fill(Color.placeholderLine)
            .frame(height: 2.5)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .cornerRadius(1.25)
    }
}

// MARK: - Add Task View
struct AddTaskView: View {
    @Environment(\.dismiss) var dismiss
    @State private var title: String = ""
    @State private var description: String = ""
    var onSave: (String, String) -> Void
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Task Details").foregroundColor(Color.secondaryText)) {
                    TextField("Task Title", text: $title)
                        .listRowBackground(Color.cardBackground)
                    TextField("Description (Optional)", text: $description, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                        .listRowBackground(Color.cardBackground)
                }
                Section {
                    Button("Add Task") {
                        if !title.isEmpty {
                            onSave(title, description)
                            dismiss()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.columnBackground.opacity(0.8))
                    .disabled(title.isEmpty)
                }
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if !title.isEmpty {
                            onSave(title, description)
                            dismiss()
                        }
                    }
                    .disabled(title.isEmpty)
                }
            }
            .background(Color.appBackground.ignoresSafeArea())
            .scrollContentBackground(.hidden)
        }
        .accentColor(Color.primaryText)
    }
}

// Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ContentView()
                .preferredColorScheme(.light)
                .previewDisplayName("Light Mode")
            ContentView()
                .preferredColorScheme(.dark)
                .previewDisplayName("Dark Mode")
        }
    }
}
