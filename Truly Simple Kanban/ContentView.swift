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
                AddTaskView { title, description in
                    self.appendNewTaskClosure(title, description)
                }
            }
            .sheet(item: $taskToEdit) { taskToActuallyEdit in
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
            .onChange(of: tasks) { newTasksValue in
                self.saveTasksClosure(newTasksValue)
            }
            .onChange(of: draggedTask) { newDraggedTaskValue in
                if newDraggedTaskValue == nil {
                    NSLog("[KanbanBoardView] Drag ended. Clearing intraColumnDropPlaceholderId.")
                    intraColumnDropPlaceholderId = nil
                } else {
                    NSLog("[KanbanBoardView] Drag started with task: %@", newDraggedTaskValue!.title)
                }
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
                filteredTasksClosure: self.filteredTasks,
                deleteTaskClosure: self.deleteTask,
                saveTasksClosure: PersistenceService.shared.saveTasks,
                appendNewTaskClosure: self.appendNewTask,
                updateTaskClosure: self.updateTask
            )
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .accentColor(Color.primaryText)
    }

    // MARK: - Data Handling Methods
    private func filteredTasks(for status: TaskStatus) -> [Task] {
        return tasks.filter { $0.status == status }
             .sorted { $0.orderIndex < $1.orderIndex }
    }

    private func deleteTask(_ taskToDelete: Task) {
        let statusOfDeletedTask = taskToDelete.status
        tasks.removeAll { $0.id == taskToDelete.id }
        reindexTasks(inColumn: statusOfDeletedTask)
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
            reindexTasks(inColumn: oldStatus)

            let tasksInNewColumn = tasks.filter { $0.status == newStatus && $0.id != id }
            let maxOrderIndexInNewColumn = tasksInNewColumn.map { $0.orderIndex }.max() ?? -1.0
            tasks[index].orderIndex = maxOrderIndexInNewColumn + 1.0
            
            reindexTasks(inColumn: newStatus)
        }
    }

    private func reindexTasks(inColumn status: TaskStatus) {
        let taskIndicesInColumn = tasks.indices.filter { tasks[$0].status == status }
        var columnTasksToSort = taskIndicesInColumn.map { tasks[$0] }
        columnTasksToSort.sort { $0.orderIndex < $1.orderIndex }

        for (newOrder, taskToReindex) in columnTasksToSort.enumerated() {
            if let originalTaskIndexInMainArray = tasks.firstIndex(where: { $0.id == taskToReindex.id }) {
                tasks[originalTaskIndexInMainArray].orderIndex = Double(newOrder)
            }
        }
    }
}

// MARK: - Component Views (Defined at File Scope)

struct KanbanColumnView: View {
    let status: TaskStatus
    let tasks: [Task]
    @Binding var allTasks: [Task]
    @Binding var draggedTask: Task? // This is the @State from ContentView, passed as @Binding
    @Binding var dropPlaceholderId: UUID?
    var onEditTask: (Task) -> Void
    var onDeleteTask: (Task) -> Void

    @State private var isColumnTargetedForEndDrop: Bool = false
    @State private var endDropTargetDebounceTimer: Timer?

    init(
        status: TaskStatus,
        tasks: [Task],
        allTasks: Binding<[Task]>,
        draggedTask: Binding<Task?>,
        dropPlaceholderId: Binding<UUID?>,
        onEditTask: @escaping (Task) -> Void,
        onDeleteTask: @escaping (Task) -> Void
    ) {
        self.status = status
        self.tasks = tasks
        self._allTasks = allTasks
        self._draggedTask = draggedTask
        self._dropPlaceholderId = dropPlaceholderId
        self.onEditTask = onEditTask
        self.onDeleteTask = onDeleteTask
    }
    
    @ViewBuilder
    private func taskSlotView(_ task: Task) -> some View {
        VStack(spacing: 0) {
            if dropPlaceholderId == task.id && self.draggedTask != nil && self.draggedTask!.id != task.id {
                DropPlaceholderView().padding(.bottom, 4)
            }
            // Pass isBeingDragged state to TaskCardView
            TaskCardView(task: task, onTap: { onEditTask(task) }, isBeingDragged: self.draggedTask?.id == task.id)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onDrag {
            NSLog("[TaskSlot %@] onDrag started for task: %@", status.rawValue, task.title)
            self.draggedTask = task
            return NSItemProvider(object: task.id.uuidString as NSString)
        }
        .dropDestination(for: String.self) { receivedItems, location in
            guard let currentDraggedTask = self.draggedTask, currentDraggedTask.id.uuidString == receivedItems.first else { return false }
            guard currentDraggedTask.id != task.id else { return false }
            NSLog("[TaskSlotDrop ACTION] Dropped task %@ to insert before %@", currentDraggedTask.title, task.title)
            if let draggedIndex = allTasks.firstIndex(where: { $0.id == currentDraggedTask.id }) {
                var mutableDraggedTask = allTasks.remove(at: draggedIndex); let oldStatus = mutableDraggedTask.status
                mutableDraggedTask.status = self.status; mutableDraggedTask.orderIndex = task.orderIndex - 0.5
                if let targetIndexInAllTasks = allTasks.firstIndex(where: { $0.id == task.id }) {
                    allTasks.insert(mutableDraggedTask, at: targetIndexInAllTasks)
                } else { allTasks.append(mutableDraggedTask) }
                let tcTasks = allTasks.filter{$0.status == self.status}.sorted{$0.orderIndex < $1.orderIndex}; for i in 0..<tcTasks.count { if let idx = allTasks.firstIndex(where:{$0.id == tcTasks[i].id}) {allTasks[idx].orderIndex = Double(i)}}
                if oldStatus != self.status { let scTasks = allTasks.filter{$0.status == oldStatus}.sorted{$0.orderIndex < $1.orderIndex}; for i in 0..<scTasks.count {if let idx = allTasks.firstIndex(where:{$0.id == scTasks[i].id}) {allTasks[idx].orderIndex = Double(i)}}}
                
                DispatchQueue.main.async {
                    self.dropPlaceholderId = nil
                    self.draggedTask = nil
                }
                return true
            }
            return false
        } isTargeted: { isTargetedOverSlot in
            if isTargetedOverSlot && self.draggedTask != nil && self.draggedTask!.id != task.id { // Use self.draggedTask
                if dropPlaceholderId != task.id {
                    NSLog("[TaskSlot Target SET] Slot for task: %@, Placeholder: %@", task.title, task.id.uuidString)
                    dropPlaceholderId = task.id
                }
                if isColumnTargetedForEndDrop {
                    NSLog("[TaskSlot Target SET] Task slot for %@ targeted, ensuring isColumnTargetedForEndDrop is false.", task.title)
                    self.endDropTargetDebounceTimer?.invalidate()
                    isColumnTargetedForEndDrop = false
                }
            } else {
                if dropPlaceholderId == task.id {
                    NSLog("[TaskSlot Target CLEAR] Slot for task: %@, Placeholder was: %@", task.title, task.id.uuidString)
                    dropPlaceholderId = nil
                }
            }
        }
        .contextMenu { Button(role: .destructive) { onDeleteTask(task) } label: { Label("Delete Task", systemImage: "trash") } }
    }

    var body: some View {
        let showColumnOverlay = isColumnTargetedForEndDrop && dropPlaceholderId == nil
        
        return VStack(alignment: .leading, spacing: 12) {
            Text(status.rawValue.uppercased())
                .font(.system(size: 14, weight: .semibold, design: .rounded)).kerning(0.5).padding(.horizontal, 8).padding(.bottom, 8).foregroundColor(status.accentColor)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .center, spacing: 0) {
                    ForEach(tasks) { task in
                        taskSlotView(task)
                    }
                    Rectangle()
                        .fill(Color.clear)
                        .frame(maxWidth: .infinity)
                        .frame(height: tasks.isEmpty ? 400 : 100) // Adjusted height
                        .contentShape(Rectangle())
                        .dropDestination(for: String.self) { receivedItems, location in
                            NSLog("[EndColumnDrop] ACTION closure entered. Current dropPlaceholderId: %@", self.dropPlaceholderId?.uuidString ?? "nil")
                            if self.dropPlaceholderId != nil {
                                NSLog("[EndColumnDrop ACTION] Yielding because dropPlaceholderId is unexpectedly SET: %@", self.dropPlaceholderId?.uuidString ?? "nil")
                                return false
                            }
                            guard let currentDraggedTask = self.draggedTask, currentDraggedTask.id.uuidString == receivedItems.first else {
                                NSLog("[EndColumnDrop ACTION] Guard failed: No dragged task or ID mismatch.")
                                return false
                            }
                            NSLog("[EndColumnDrop ACTION] Processing drop of task %@ at end of column %@", currentDraggedTask.title, self.status.rawValue)
                            if let draggedIndex = allTasks.firstIndex(where: { $0.id == currentDraggedTask.id }) {
                                var itemToMove = allTasks[draggedIndex]; let originalStatus = itemToMove.status
                                if originalStatus == self.status { allTasks.remove(at: draggedIndex) }
                                itemToMove.status = self.status
                                let otherTasksInColumn = allTasks.filter { $0.status == self.status && $0.id != currentDraggedTask.id }
                                itemToMove.orderIndex = (otherTasksInColumn.map { $0.orderIndex }.max() ?? -1.0) + 1.0
                                if let existingIndex = allTasks.firstIndex(where: { $0.id == itemToMove.id}) { allTasks[existingIndex] = itemToMove } else { allTasks.append(itemToMove) }
                                let tcTasks = allTasks.filter{$0.status == self.status}.sorted{$0.orderIndex < $1.orderIndex}; for i in 0..<tcTasks.count { if let idx = allTasks.firstIndex(where:{$0.id == tcTasks[i].id}) {allTasks[idx].orderIndex = Double(i)}}
                                if originalStatus != self.status { let scTasks = allTasks.filter{$0.status == originalStatus}.sorted{$0.orderIndex < $1.orderIndex}; for i in 0..<scTasks.count {if let idx = allTasks.firstIndex(where:{$0.id == scTasks[i].id}) {allTasks[idx].orderIndex = Double(i)}}}
                                
                                DispatchQueue.main.async {
                                    self.dropPlaceholderId = nil
                                    self.draggedTask = nil
                                }
                                return true
                            }
                            NSLog("[EndColumnDrop ACTION] Failed to find dragged task in allTasks.")
                            return false
                        } isTargeted: { isOverEndSpacer in
                            // MODIFIED: Debounced logic for end spacer targeting
                            self.endDropTargetDebounceTimer?.invalidate()

                            if isOverEndSpacer && self.draggedTask != nil { // Use self.draggedTask
                                if self.dropPlaceholderId != nil {
                                    NSLog("[EndColumnSpacer Hover] Clearing task placeholder (was %@). End spacer is primary.", self.dropPlaceholderId!.uuidString)
                                    self.dropPlaceholderId = nil
                                }
                                
                                self.endDropTargetDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { _ in // Increased debounce interval
                                    if self.draggedTask != nil && self.dropPlaceholderId == nil {
                                        if !self.isColumnTargetedForEndDrop {
                                            NSLog("[EndColumnSpacer DEBOUNCED] Setting isColumnTargetedForEndDrop = true (Highlight ON)")
                                            self.isColumnTargetedForEndDrop = true
                                        }
                                    } else {
                                        if self.isColumnTargetedForEndDrop {
                                             NSLog("[EndColumnSpacer DEBOUNCED] Conditions NO LONGER MET (placeholderId: %@), setting isColumnTargetedForEndDrop = false", self.dropPlaceholderId?.uuidString ?? "nil")
                                            self.isColumnTargetedForEndDrop = false
                                        }
                                    }
                                }
                            } else {
                                if self.isColumnTargetedForEndDrop {
                                    NSLog("[EndColumnSpacer Hover Exit] Setting isColumnTargetedForEndDrop = false (Highlight OFF)")
                                    self.isColumnTargetedForEndDrop = false
                                }
                            }
                        }
                }
            }
        }
        .padding(12).frame(width: 300, height: 650).background(Color.columnBackground).cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.subtleBorder, lineWidth: 0.75))
        .overlay(Group { if showColumnOverlay { RoundedRectangle(cornerRadius: 12).fill(Color.accentColor.opacity(0.1)) } })
    }
}

struct TaskCardView: View {
    let task: Task
    var onTap: (() -> Void)? = nil
    var isBeingDragged: Bool // New parameter

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
        .opacity(isBeingDragged ? 0.2 : 1.0) // Apply opacity here
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
            Section {
                TextField("Task Title", text: $title)
                    .listRowBackground(Color.cardBackground)
                TextField("Description (Optional)", text: $description, axis: .vertical)
                    .lineLimit(3...)
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
                .listRowBackground(Color.columnBackground)
                .disabled(title.isEmpty)
            }
        }
        .navigationTitle("New Task")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") { dismiss() }
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
        .scrollContentBackground(.hidden)
    }
}

// REMOVED DropTaskDelegate and DropTaskOnTaskDelegate classes

// MARK: - Preview (Defined at File Scope)
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .preferredColorScheme(.light)
    }
}
