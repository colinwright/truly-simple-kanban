// ContentView.swift
import UniformTypeIdentifiers
import SwiftUI

// Custom ViewModifier for conditional toolbar background
struct ToolbarBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, macOS 13.0, *) {
            content
                .toolbarBackground(Color.appBackground, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        } else {
            content
        }
    }
}

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
    private var navigationToolbar: some ToolbarContent {
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
            .toolbar { navigationToolbar }
            .modifier(ToolbarBackgroundModifier())
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
            .onChange(of: tasks) { oldValue, newValue in self.saveTasksClosure(newValue) }
            .onChange(of: draggedTask) { oldValue, newValue in if newValue == nil { intraColumnDropPlaceholderId = nil } }
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
    @Binding var draggedTask: Task?
    @Binding var dropPlaceholderId: UUID?
    var onEditTask: (Task) -> Void
    var onDeleteTask: (Task) -> Void
    @StateObject private var columnDropDelegate: DropTaskDelegate

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
        self._columnDropDelegate = StateObject(wrappedValue: DropTaskDelegate(columnStatus: status, tasks: allTasks, draggedTask: draggedTask))
    }
    
    @ViewBuilder
    private func taskRowView(_ task: Task) -> some View {
        if dropPlaceholderId == task.id,
           let currentDraggedTask = draggedTask,
           currentDraggedTask.id != task.id,
           currentDraggedTask.status == self.status {
            DropPlaceholderView()
        }
        TaskCardView(task: task, onTap: { onEditTask(task) })
            .padding(.vertical, 6)
            .onDrag {
                self.draggedTask = task
                return NSItemProvider(object: task.id.uuidString as NSString)
            }
            .onDrop(of: [UTType.plainText],
                    delegate: DropTaskOnTaskDelegate(
                        targetTask: task,
                        tasks: $allTasks,
                        draggedTask: $draggedTask,
                        dropPlaceholderId: $dropPlaceholderId,
                        currentColumnStatus: self.status
                    )
            )
            .contextMenu {
                Button(role: .destructive) { onDeleteTask(task) } label: {
                    Label("Delete Task", systemImage: "trash")
                }
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(status.rawValue.uppercased())
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .kerning(0.5)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                .foregroundColor(status.accentColor)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(tasks) { task in
                        taskRowView(task)
                    }
                    Spacer().frame(minHeight: 10)
                }
            }
        }
        .padding(12)
        .frame(width: 300, height: 650)
        .background(Color.columnBackground)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.subtleBorder, lineWidth: 0.75))
        .overlay(columnDropDelegate.columnTargetFeedback())
        .onDrop(of: [UTType.plainText], delegate: columnDropDelegate)
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

struct TaskCardView: View {
    let task: Task
    var onTap: (() -> Void)? = nil

    var body: some View {
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
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
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

// MARK: - Drop Delegates (Defined at File Scope)
class DropTaskDelegate: ObservableObject, DropDelegate {
    let columnStatus: TaskStatus
    @Binding var tasks: [Task]
    @Binding var draggedTask: Task?
    @Published var isTargeted: Bool = false

    init(columnStatus: TaskStatus, tasks: Binding<[Task]>, draggedTask: Binding<Task?>) {
        self.columnStatus = columnStatus
        self._tasks = tasks
        self._draggedTask = draggedTask
    }

    func performDrop(info: DropInfo) -> Bool {
        DispatchQueue.main.async { self.isTargeted = false }
        guard let dragged = self.draggedTask,
              let sourceTaskIndexInAllTasks = tasks.firstIndex(where: { $0.id == dragged.id })
        else {
            DispatchQueue.main.async { self.draggedTask = nil }
            return false
        }

        var mutableTasks = tasks

        let previousStatus = mutableTasks[sourceTaskIndexInAllTasks].status

        if previousStatus != columnStatus {
            mutableTasks[sourceTaskIndexInAllTasks].status = columnStatus
        }
        
        let otherTasksInTargetColumn = mutableTasks.filter { $0.status == columnStatus && $0.id != dragged.id }
        let maxOrderIndexInTargetColumn = otherTasksInTargetColumn.map { $0.orderIndex }.max() ?? -1.0
        mutableTasks[sourceTaskIndexInAllTasks].orderIndex = maxOrderIndexInTargetColumn + 1.0
        
        // FIXED: var to let
        let finalTasksInTargetColumn = mutableTasks.filter { $0.status == columnStatus }.sorted { $0.orderIndex < $1.orderIndex }
        for i in 0..<finalTasksInTargetColumn.count {
            if let originalTaskIndex = mutableTasks.firstIndex(where: { $0.id == finalTasksInTargetColumn[i].id }) {
                mutableTasks[originalTaskIndex].orderIndex = Double(i)
            }
        }
        
        if previousStatus != columnStatus {
            // FIXED: var to let
            let finalTasksInSourceColumn = mutableTasks.filter { $0.status == previousStatus }.sorted { $0.orderIndex < $1.orderIndex }
            for i in 0..<finalTasksInSourceColumn.count {
                if let originalTaskIndex = mutableTasks.firstIndex(where: { $0.id == finalTasksInSourceColumn[i].id }) {
                    mutableTasks[originalTaskIndex].orderIndex = Double(i)
                }
            }
        }
        
        self.tasks = mutableTasks
        DispatchQueue.main.async { self.draggedTask = nil }
        return true
    }

    func validateDrop(info: DropInfo) -> DropProposal? {
        guard self.draggedTask != nil else { return nil }
        return DropProposal(operation: .move)
    }

    func dropEntered(info: DropInfo) {
        guard self.draggedTask != nil else { return }
        DispatchQueue.main.async { self.isTargeted = true }
    }

    func dropExited(info: DropInfo) {
        DispatchQueue.main.async { self.isTargeted = false }
    }
    
    func columnTargetFeedback() -> some View {
        if isTargeted {
            return AnyView(RoundedRectangle(cornerRadius: 12).fill(Color.accentColor.opacity(0.1)))
        }
        return AnyView(EmptyView())
    }
}

struct DropTaskOnTaskDelegate: DropDelegate {
    let targetTask: Task
    @Binding var tasks: [Task]
    @Binding var draggedTask: Task?
    @Binding var dropPlaceholderId: UUID?
    let currentColumnStatus: TaskStatus

    func performDrop(info: DropInfo) -> Bool {
        self.dropPlaceholderId = nil
        guard let dragged = self.draggedTask,
              dragged.id != targetTask.id
        else {
            DispatchQueue.main.async { self.draggedTask = nil }
            return false
        }

        var mutableTasks = tasks
        guard let draggedTaskOriginalArrayIndex = mutableTasks.firstIndex(where: { $0.id == dragged.id })
        else {
            DispatchQueue.main.async { self.draggedTask = nil }
            return false
        }
        
        var itemToMove = mutableTasks.remove(at: draggedTaskOriginalArrayIndex)
        let previousStatus = itemToMove.status
        itemToMove.status = targetTask.status

        let targetTaskArrayIndexInMutable = mutableTasks.firstIndex(where: { $0.id == targetTask.id })
        
        if let actualTargetIndex = targetTaskArrayIndexInMutable {
            mutableTasks.insert(itemToMove, at: actualTargetIndex)
        } else {
            itemToMove.orderIndex = (mutableTasks.filter({$0.status == targetTask.status}).map({$0.orderIndex}).max() ?? -1.0) + 1.0
            mutableTasks.append(itemToMove)
        }
        
        let finalTargetColumnStatus = itemToMove.status
        // FIXED: var to let
        let tasksInFinalTargetColumn = mutableTasks.filter { $0.status == finalTargetColumnStatus }.sorted(by: { taskA, taskB in
            if taskA.id == itemToMove.id && taskB.id == targetTask.id { return true }
            if taskB.id == itemToMove.id && taskA.id == targetTask.id { return false }
            return taskA.orderIndex < taskB.orderIndex
        })

        for i in 0..<tasksInFinalTargetColumn.count {
            if let originalTaskIndex = mutableTasks.firstIndex(where: { $0.id == tasksInFinalTargetColumn[i].id }) {
                mutableTasks[originalTaskIndex].orderIndex = Double(i)
            }
        }
        
        if previousStatus != finalTargetColumnStatus {
            // FIXED: var to let
            let tasksInSourceColumn = mutableTasks.filter { $0.status == previousStatus }.sorted { $0.orderIndex < $1.orderIndex }
            for i in 0..<tasksInSourceColumn.count {
                if let originalTaskIndex = mutableTasks.firstIndex(where: { $0.id == tasksInSourceColumn[i].id }) {
                    mutableTasks[originalTaskIndex].orderIndex = Double(i)
                }
            }
        }
        
        self.tasks = mutableTasks
        DispatchQueue.main.async { self.draggedTask = nil }
        return true
    }

    func validateDrop(info: DropInfo) -> DropProposal? {
        guard let dragged = self.draggedTask,
              dragged.id != targetTask.id
        else { return nil }
        return DropProposal(operation: .move)
    }

    func dropEntered(info: DropInfo) {
        guard let dragged = self.draggedTask,
              dragged.id != targetTask.id
        else { return }
        
        if dragged.status == targetTask.status {
            self.dropPlaceholderId = targetTask.id
        } else {
            self.dropPlaceholderId = nil
        }
    }

    func dropExited(info: DropInfo) {
        if self.dropPlaceholderId == targetTask.id {
             self.dropPlaceholderId = nil
        }
    }
}

// MARK: - Preview (Defined at File Scope)
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .preferredColorScheme(.light)
    }
}
