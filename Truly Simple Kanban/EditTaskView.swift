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
        ToolbarItem(placement: .navigationBarLeading) { // Or .cancellationAction for standard iOS behavior
            Button("Cancel") { dismiss() }
        }
        // If you want a "Done" or "Save" button in the toolbar as well:
        // ToolbarItem(placement: .confirmationAction) { // Or .navigationBarTrailing
        //     Button("Done") {
        //         if !editingTitle.isEmpty {
        //             onSave(task.id, editingTitle, editingDescription, editingStatus)
        //             dismiss()
        //         }
        //     }
        //     .disabled(editingTitle.isEmpty)
        // }
    }

    var body: some View {
        // NavigationView has been removed from here
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
            
            Section {
                Button("Save Changes") {
                    if !editingTitle.isEmpty {
                        onSave(task.id, editingTitle, editingDescription, editingStatus)
                        dismiss()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowBackground(Color.columnBackground)
            }
            
            if onDelete != nil {
                Section {
                    Button("Delete Task", role: .destructive) {
                        onDelete?(task.id)
                        // ContentView handles taskToEdit = nil to dismiss after onDelete completes
                        // If not handled by ContentView, you might want to dismiss here too,
                        // but it's generally better if the presenter dismisses after the action.
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.columnBackground)
                }
            }
        }
        .navigationTitle("Edit Task") // Applies to the presenting NavigationView's bar
        .toolbar { viewToolbar }      // Applies to the presenting NavigationView's bar
        .background(Color.appBackground.ignoresSafeArea()) // Apply to Form or a wrapping view
        .scrollContentBackground(.hidden) // iOS 16+
        .accentColor(Color.primaryText) // Applies to interactive elements within this view
    }
}

// Optional Preview for EditTaskView
struct EditTaskView_Previews: PreviewProvider {
    static var previews: some View {
        // To make the preview look right (with a nav bar), wrap it in a NavigationView here
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
        .preferredColorScheme(.light)
    }
}
