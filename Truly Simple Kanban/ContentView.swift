// ContentView.swift
import UniformTypeIdentifiers
import SwiftUI
import os

// Encapsulates the main board UI and its modifiers.
struct KanbanBoardView: View {
    @Binding var tasks: [Task]
    @Binding var showingAddTaskSheet: Bool
    @Binding var draggedTask: Task?
    @Binding var taskToEdit: Task?
    @Binding var intraColumnDropPlaceholderId: UUID?
    @Binding var currentDragSessionID: UUID?
    @Binding var ignoreNextDragStartOnTaskID: UUID? // New Binding

    let filteredTasksClosure: (TaskStatus) -> [Task]
    let deleteTaskClosure: (Task) -> Void
    let saveTasksClosure: ([Task]) -> Void
    let appendNewTaskClosure: (String, String) -> Void
    let updateTaskClosure: (UUID, String, String, TaskStatus) -> Void

    private var kanbanBoardContent: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 20) {
                ForEach(TaskStatus.allCases) { status in
                    KanbanColumnView(
                        status: status,
                        tasks: filteredTasksClosure(status),
                        allTasks: $tasks,
                        draggedTask: $draggedTask,
                        dropPlaceholderId: $intraColumnDropPlaceholderId,
                        currentDragSessionID: $currentDragSessionID,
                        ignoreNextDragStartOnTaskID: $ignoreNextDragStartOnTaskID, // Pass binding
                        onEditTask: { task in self.taskToEdit = task },
                        onDeleteTask: { task in self.deleteTaskClosure(task) }
                    )
                }
            }
            .padding()
        }
        .background(Color.appBackground.edgesIgnoringSafeArea(.all))
    }

    @ToolbarContentBuilder
    private var navigationToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button { showingAddTaskSheet = true } label: {
                Image(systemName: "plus.circle.fill").font(.title2).foregroundColor(Color.primaryText)
            }
        }
        ToolbarItem(placement: .principal) {
             Text("Truly Simple Kanban").font(.system(size: 12, weight: .medium)).foregroundColor(Color.secondaryText)
         }
    }
    
    var body: some View {
        kanbanBoardContent
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { navigationToolbarContent }
            .toolbarBackground(Color.appBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $showingAddTaskSheet) {
                NavigationView {
                    AddTaskView { title, description in
                        self.appendNewTaskClosure(title, description)
                    }
                }
            }
            .sheet(item: $taskToEdit) { taskToActuallyEdit in
                NavigationView {
                    EditTaskView(
                        task: taskToActuallyEdit,
                        onSave: { id, newTitle, newDescription, newStatus in
                            self.updateTaskClosure(id, newTitle, newDescription, newStatus)
                            self.taskToEdit = nil
                        },
                        onDelete: { taskIdToDelete in
                            if let taskIndex = tasks.firstIndex(where: { $0.id == taskIdToDelete }) {
                                self.deleteTaskClosure(tasks[taskIndex])
                            }
                            self.taskToEdit = nil
                        }
                    )
                }
            }
            .onChange(of: tasks) { currentTasksSnapshot in
                 self.saveTasksClosure(currentTasksSnapshot)
            }
    }
}


// MARK: - Main Content View (Root View of the App)
struct ContentView: View {
    @State private var tasks: [Task] = PersistenceService.shared.loadTasks()
    @State private var showingAddTaskSheet = false
    @State private var draggedTask: Task?
    @State private var taskToEdit: Task?
    @State private var intraColumnDropPlaceholderId: UUID?
    @State private var currentDragSessionID: UUID?
    @State private var ignoreNextDragStartOnTaskID: UUID? // New State

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
                draggedTask: $draggedTask,
                taskToEdit: $taskToEdit,
                intraColumnDropPlaceholderId: $intraColumnDropPlaceholderId,
                currentDragSessionID: $currentDragSessionID,
                ignoreNextDragStartOnTaskID: $ignoreNextDragStartOnTaskID,
                filteredTasksClosure: self.filteredTasks,
                deleteTaskClosure: self.deleteTask,
                saveTasksClosure: { tasksToSave in
                    PersistenceService.shared.saveTasks(tasksToSave)
                },
                appendNewTaskClosure: self.appendNewTask,
                updateTaskClosure: self.updateTask
            )
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .accentColor(Color.primaryText)
    }

    private func filteredTasks(for status: TaskStatus) -> [Task] {
        return tasks.filter { $0.status == status }
             .sorted { $0.orderIndex < $1.orderIndex }
    }

    private func deleteTask(_ taskToDelete: Task) {
        let statusOfDeletedTask = taskToDelete.status
        tasks.removeAll { $0.id == taskToDelete.id }
        reindexTasksGlobally(inColumn: statusOfDeletedTask)
    }

    private func appendNewTask(title: String, description: String) {
        let todoTasks = tasks.filter { $0.status == .todo }
        let nextOrderIndex = (todoTasks.map { $0.orderIndex }.max() ?? -1.0) + 1.0
        let newTask = Task(title: title, description: description.isEmpty ? nil : description, status: .todo, orderIndex: nextOrderIndex)
        tasks.append(newTask)
    }

    private func updateTask(id: UUID, newTitle: String, newDescription: String, newStatus: TaskStatus) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        
        let oldStatus = tasks[index].status
        tasks[index].title = newTitle
        tasks[index].description = newDescription.isEmpty ? nil : newDescription
        
        if oldStatus != newStatus {
            tasks[index].status = newStatus
            let tasksInNewColumn = tasks.filter { $0.status == newStatus && $0.id != id }
            let maxOrderIndexInNewColumn = tasksInNewColumn.map { $0.orderIndex }.max() ?? -1.0
            tasks[index].orderIndex = maxOrderIndexInNewColumn + 1.0
            
            reindexTasksGlobally(inColumn: oldStatus)
            reindexTasksGlobally(inColumn: newStatus)
        }
    }

    private func reindexTasksGlobally(inColumn status: TaskStatus) {
        let taskIndicesInColumn = tasks.indices.filter { tasks[$0].status == status }
        var columnTasksToSort = taskIndicesInColumn.map { tasks[$0] }
        columnTasksToSort.sort { $0.orderIndex < $1.orderIndex }

        for (newOrder, taskToReindex) in columnTasksToSort.enumerated() {
            if let originalTaskIndexInMainArray = tasks.firstIndex(where: { $0.id == taskToReindex.id }) {
                if tasks[originalTaskIndexInMainArray].orderIndex != Double(newOrder) {
                    tasks[originalTaskIndexInMainArray].orderIndex = Double(newOrder)
                }
            }
        }
    }
}


struct KanbanColumnView: View {
    let status: TaskStatus
    let tasks: [Task]
    @Binding var allTasks: [Task]
    @Binding var draggedTask: Task?
    @Binding var dropPlaceholderId: UUID?
    @Binding var currentDragSessionID: UUID?
    @Binding var ignoreNextDragStartOnTaskID: UUID? // New Binding
    var onEditTask: (Task) -> Void
    var onDeleteTask: (Task) -> Void

    @State private var isColumnTargetedForEndDrop: Bool = false

    private func reindexAffectedColumn(_ columnStatus: TaskStatus) {
        // ... (reindex logic remains the same)
        var tasksToReindex = allTasks.filter { $0.status == columnStatus }
        tasksToReindex.sort { $0.orderIndex < $1.orderIndex }
        for (newOrderIndex, taskInReindexList) in tasksToReindex.enumerated() {
            if let masterListIndex = allTasks.firstIndex(where: { $0.id == taskInReindexList.id }) {
                if allTasks[masterListIndex].orderIndex != Double(newOrderIndex) {
                     allTasks[masterListIndex].orderIndex = Double(newOrderIndex)
                }
            }
        }
    }

    @ViewBuilder
    private func taskSlotView(_ task: Task) -> some View {
        VStack(spacing: 0) {
            if dropPlaceholderId == task.id && self.draggedTask != nil && self.draggedTask!.id != task.id {
                DropPlaceholderView().padding(.bottom, 4)
            }
            TaskCardView(task: task, onTap: { onEditTask(task) },
                         isBeingDragged: self.draggedTask?.id == task.id && self.currentDragSessionID != nil)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onDrag {
            // **PRIORITY 1: Check ignore flag**
            if self.ignoreNextDragStartOnTaskID == task.id {
                NSLog("[TaskSlot %@] onDrag: IGNORING for task '%@' due to ignoreNextDragStartOnTaskID flag.", status.rawValue, task.title)
            }
            // **PRIORITY 2: Start or supersede drag**
            else if self.draggedTask?.id != task.id {
                let oldDraggedTaskTitle = self.draggedTask?.title
                self.draggedTask = task
                self.currentDragSessionID = UUID()
                if oldDraggedTaskTitle == nil {
                    NSLog("[TaskSlot %@] onDrag: INITIATED New Session %@ for task '%@'", status.rawValue, self.currentDragSessionID!.uuidString, task.title)
                } else {
                    NSLog("[TaskSlot %@] onDrag: SUPERSEDED (old: '%@'), New Session %@ for task '%@'", status.rawValue, oldDraggedTaskTitle!, self.currentDragSessionID!.uuidString, task.title)
                }
            }
            // **PRIORITY 3: Continuation of existing drag (ensure session ID)**
            else if self.currentDragSessionID == nil { // Should only happen if task is already draggedTask but session was lost
                self.currentDragSessionID = UUID()
                NSLog("[TaskSlot %@] onDrag: RECOVERED Session %@ for task '%@'", status.rawValue, self.currentDragSessionID!.uuidString, task.title)
            }
            // else: Task is already draggedTask and has a sessionID - normal continuation.

            return NSItemProvider(object: task.id.uuidString as NSString)
        }
        .dropDestination(for: String.self) { receivedItems, location in
            guard let activeDraggedTask = self.draggedTask,
                  let activeSessionID = self.currentDragSessionID else {
                NSLog("[TaskSlotDrop REJECT] No active dragged task or session ID.")
                return false
            }
            guard let receivedTaskIDString = receivedItems.first,
                  activeDraggedTask.id.uuidString == receivedTaskIDString else {
                NSLog("[TaskSlotDrop REJECT] Received item ID '%@' != active task ID '%@'. Session: %@",
                      receivedItems.first ?? "nil", activeDraggedTask.id.uuidString, activeSessionID.uuidString)
                return false
            }
            guard activeDraggedTask.id != task.id else {
                NSLog("[TaskSlotDrop REJECT] Drop on self. Session: %@", activeSessionID.uuidString)
                return false
            }
            
            let droppedTaskID = activeDraggedTask.id // Capture before clearing
            
            if let draggedTaskGlobalIndex = allTasks.firstIndex(where: { $0.id == activeDraggedTask.id }) {
                var mutableDraggedTask = allTasks.remove(at: draggedTaskGlobalIndex)
                let oldStatus = mutableDraggedTask.status
                mutableDraggedTask.status = self.status
                mutableDraggedTask.orderIndex = task.orderIndex - 0.5
                allTasks.append(mutableDraggedTask)

                reindexAffectedColumn(self.status)
                if oldStatus != self.status { reindexAffectedColumn(oldStatus) }
                
                // Synchronous state clearing AND set ignore flag
                self.ignoreNextDragStartOnTaskID = droppedTaskID
                self.draggedTask = nil
                self.dropPlaceholderId = nil
                self.isColumnTargetedForEndDrop = false
                self.currentDragSessionID = nil
                NSLog("[TaskSlotDrop SUCCESS] Session %@ ended. Set ignoreNextDragStartOnTaskID for '%@'.", activeSessionID.uuidString, droppedTaskID.uuidString)

                DispatchQueue.main.async { // Clear the ignore flag on the next run loop cycle
                    if self.ignoreNextDragStartOnTaskID == droppedTaskID {
                        self.ignoreNextDragStartOnTaskID = nil
                        NSLog("[TaskSlotDrop async] Cleared ignoreNextDragStartOnTaskID for '%@'.", droppedTaskID.uuidString)
                    }
                }
                return true
            }
            NSLog("[TaskSlotDrop FAIL] Could not find task. Session %@.", activeSessionID.uuidString)
            self.draggedTask = nil // Cleanup on failure
            self.currentDragSessionID = nil
            // Explicitly clear ignore flag if set for this failed attempt
            if self.ignoreNextDragStartOnTaskID == droppedTaskID { self.ignoreNextDragStartOnTaskID = nil }
            return false
        } isTargeted: { isTargetedOverSlot in
            // ... (targeting logic remains the same) ...
            guard self.currentDragSessionID != nil, let currentDraggedTask = self.draggedTask else {
                if self.dropPlaceholderId != nil { self.dropPlaceholderId = nil }
                if self.isColumnTargetedForEndDrop { self.isColumnTargetedForEndDrop = false }
                return
            }
            if isTargetedOverSlot && currentDraggedTask.id != task.id {
                if self.dropPlaceholderId != task.id { self.dropPlaceholderId = task.id }
                if self.isColumnTargetedForEndDrop { self.isColumnTargetedForEndDrop = false }
            } else {
                if self.dropPlaceholderId == task.id { self.dropPlaceholderId = nil }
            }
        }
        .contextMenu { Button(role: .destructive) { onDeleteTask(task) } label: { Label("Delete Task", systemImage: "trash") } }
    }

    var body: some View {
        let showColumnOverlay = isColumnTargetedForEndDrop && dropPlaceholderId == nil && draggedTask != nil && currentDragSessionID != nil
        
        return VStack(alignment: .leading, spacing: 12) {
            Text(status.rawValue.uppercased())
                .font(.system(size: 14, weight: .semibold, design: .rounded)).kerning(0.5).padding(.horizontal, 8).padding(.bottom, 8).foregroundColor(status.accentColor)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .center, spacing: 0) {
                    ForEach(tasks) { taskItem in
                        taskSlotView(taskItem)
                    }
                    Rectangle()
                        .fill(Color.clear)
                        .frame(maxWidth: .infinity)
                        .frame(height: tasks.isEmpty ? 400 : 250)
                        .contentShape(Rectangle())
                        .dropDestination(for: String.self) { receivedItems, location in
                            guard let activeDraggedTask = self.draggedTask,
                                  let activeSessionID = self.currentDragSessionID else {
                                NSLog("[EndColumnDrop REJECT] No active drag.")
                                return false
                            }
                            guard let receivedTaskIDString = receivedItems.first,
                                  activeDraggedTask.id.uuidString == receivedTaskIDString else {
                                NSLog("[EndColumnDrop REJECT] Received ID '%@' != active task ID '%@'. Session: %@",
                                      receivedItems.first ?? "nil", activeDraggedTask.id.uuidString, activeSessionID.uuidString)
                                return false
                            }
                            if self.dropPlaceholderId != nil {
                                NSLog("[EndColumnDrop ACTION] Yielding: dropPlaceholderId set. Session: %@", activeSessionID.uuidString)
                                return false
                            }
                            
                            let droppedTaskID = activeDraggedTask.id // Capture ID
                            
                            if let draggedTaskGlobalIndex = allTasks.firstIndex(where: { $0.id == activeDraggedTask.id }) {
                                var taskToMove = allTasks.remove(at: draggedTaskGlobalIndex)
                                let originalStatus = taskToMove.status
                                taskToMove.status = self.status
                                let maxOrderIndexInColumn = allTasks.filter { $0.status == self.status }.map { $0.orderIndex }.max() ?? -1.0
                                taskToMove.orderIndex = maxOrderIndexInColumn + 1.0
                                allTasks.append(taskToMove)

                                reindexAffectedColumn(self.status)
                                if originalStatus != self.status { reindexAffectedColumn(originalStatus) }

                                // Synchronous state clearing AND set ignore flag
                                self.ignoreNextDragStartOnTaskID = droppedTaskID
                                self.draggedTask = nil
                                self.isColumnTargetedForEndDrop = false
                                self.currentDragSessionID = nil
                                NSLog("[EndColumnDrop SUCCESS] Session %@ ended. Set ignoreNextDragStartOnTaskID for '%@'.", activeSessionID.uuidString, droppedTaskID.uuidString)

                                DispatchQueue.main.async { // Clear ignore flag on next run loop
                                    if self.ignoreNextDragStartOnTaskID == droppedTaskID {
                                        self.ignoreNextDragStartOnTaskID = nil
                                        NSLog("[EndColumnDrop async] Cleared ignoreNextDragStartOnTaskID for '%@'.", droppedTaskID.uuidString)
                                    }
                                }
                                return true
                            }
                            NSLog("[EndColumnDrop FAIL] Could not find task. Session %@.", activeSessionID.uuidString)
                            self.draggedTask = nil // Cleanup on failure
                            self.currentDragSessionID = nil
                            if self.ignoreNextDragStartOnTaskID == droppedTaskID { self.ignoreNextDragStartOnTaskID = nil }
                            return false
                        } isTargeted: { isOverEndSpacer in
                             // ... (targeting logic remains the same) ...
                             guard self.currentDragSessionID != nil, self.draggedTask != nil else {
                                if self.isColumnTargetedForEndDrop { self.isColumnTargetedForEndDrop = false }
                                return
                            }
                            if isOverEndSpacer {
                                if self.dropPlaceholderId != nil { self.dropPlaceholderId = nil }
                                if !self.isColumnTargetedForEndDrop { self.isColumnTargetedForEndDrop = true }
                            } else {
                                if self.isColumnTargetedForEndDrop { self.isColumnTargetedForEndDrop = false }
                            }
                        }
                }
            }
        }
        .padding(12).frame(width: 300, height: 650).background(Color.columnBackground).cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.subtleBorder, lineWidth: 0.75))
        .overlay(Group { if showColumnOverlay { RoundedRectangle(cornerRadius: 12).fill(Color.accentColor.opacity(0.1)).animation(.easeInOut(duration: 0.2), value: showColumnOverlay) } })
    }
}

// TaskCardView, DropPlaceholderView, AddTaskView, ContentView_Previews remain the same
struct TaskCardView: View {
    let task: Task
    var onTap: (() -> Void)? = nil
    var isBeingDragged: Bool

    var body: some View {
        ZStack {
            Color.clear
            VStack(alignment: .leading, spacing: 5) {
                Text(task.title)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(Color.primaryText)
                    .lineLimit(3)
                if let description = task.description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(Color.secondaryText)
                        .lineLimit(2)
                        .padding(.top, 2)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.cardBackground)
            .cornerRadius(10)
            .overlay(
                 RoundedRectangle(cornerRadius: 10)
                     .stroke(Color.subtleBorder.opacity(0.6), lineWidth: 0.75)
            )
        }
        .contentShape(Rectangle())
        .opacity(isBeingDragged ? 0.3 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isBeingDragged)
        .onTapGesture { onTap?() }
    }
}

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
struct AddTaskView: View {
    @Environment(\.dismiss) var dismiss
    @State private var title: String = ""
    @State private var description: String = ""
    var onSave: (String, String) -> Void

    var body: some View {
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
                 Button("Add") { if !title.isEmpty { onSave(title, description); dismiss() } }
                 .disabled(title.isEmpty)
             }
        }
        .background(Color.appBackground.ignoresSafeArea())
        .scrollContentBackground(.hidden)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .preferredColorScheme(.light)
    }
}
