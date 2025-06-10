// EditTaskView.swift
import SwiftUI
import UniformTypeIdentifiers

struct EditTaskView: View {
    @Environment(\.dismiss) var dismiss
    let task: Task
    
    @State private var editingTitle: String
    @State private var editingDescription: String
    @State private var editingStatus: TaskStatus
    
    var onSave: (UUID, String, String, TaskStatus) -> Void
    var onDelete: ((UUID) -> Void)?

    init(task: Task, onSave: @escaping (UUID, String, String, TaskStatus) -> Void, onDelete: ((UUID) -> Void)? = nil) {
        self.task = task
        self._editingTitle = State(initialValue: task.title)
        self._editingDescription = State(initialValue: task.description ?? "")
        self._editingStatus = State(initialValue: task.status)
        self.onSave = onSave
        self.onDelete = onDelete
    }

    @ToolbarContentBuilder
    private var viewToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
        
        ToolbarItem(placement: .confirmationAction) {
            Button("Save") {
                if !editingTitle.isEmpty {
                    onSave(task.id, editingTitle, editingDescription, editingStatus)
                    dismiss()
                }
            }
            .disabled(editingTitle.isEmpty)
        }
    }

    var body: some View {
        // --- START OF CORRECTION ---
        // A view presented in a sheet needs its own NavigationView
        // to display a toolbar and navigation title.
        NavigationView {
            Form {
                Section(header: Text("Task Details").foregroundColor(Color.secondaryText)) {
                    TextField("Task Title", text: $editingTitle)
                        .listRowBackground(Color.cardBackground)
                    TextField("Description (Optional)", text: $editingDescription, axis: .vertical)
                        .lineLimit(3...)
                        .listRowBackground(Color.cardBackground)
                    Picker("Status", selection: $editingStatus) {
                        ForEach(TaskStatus.allCases) { status in
                            Text(status.rawValue).tag(status)
                        }
                    }
                    .listRowBackground(Color.cardBackground)
                }
                
                if onDelete != nil {
                    Section {
                        Button("Delete Task", role: .destructive) {
                            onDelete?(task.id)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.columnBackground)
                    }
                }
            }
            .navigationTitle("Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { viewToolbar }
            .background(Color.appBackground.ignoresSafeArea())
            .scrollContentBackground(.hidden)
        }
        // --- END OF CORRECTION ---
        .accentColor(Color.primaryText) // AccentColor can apply to the NavigationView
    }
}

// Optional Preview for EditTaskView (No change needed here)
struct EditTaskView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            EditTaskView(
                task: Task(id: UUID(), title: "Sample Edit Task", description: "This is a description for the task.", status: .inProgress, orderIndex: 0.0),
                onSave: { id, title, desc, status in
                    print("Preview Save: \(id), \(title), \(desc), \(status.rawValue)")
                },
                onDelete: { id in
                    print("Preview Delete: \(id)")
                }
            )
        }
        .preferredColorScheme(.dark)
    }
}
