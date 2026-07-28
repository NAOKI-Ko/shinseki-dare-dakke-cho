import SwiftUI
import SwiftData

struct GatheringListView: View {
    @Environment(\.modelContext) private var context
    @Environment(TrialManager.self) private var trialManager
    @Query(sort: [SortDescriptor(\Gathering.date, order: .reverse)])
    private var gatherings: [Gathering]

    @State private var showingAddSheet = false
    @State private var showingPurchaseSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if gatherings.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "person.3.sequence")
                            .font(.system(size: 40))
                            .foregroundStyle(AppTheme.ai.opacity(0.5))
                        Text("まだ登録がありません")
                            .font(.minchoTitle(18, relativeTo: .title3))
                            .foregroundStyle(AppTheme.ink)
                        Text("法事や帰省などの集まりを登録すると、誰が来たかをあとで確認できます。")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.inkSoft)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.paper)
                } else {
                    List {
                        ForEach(gatherings) { gathering in
                            NavigationLink(value: gathering) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(gathering.title).font(.body.weight(.semibold))
                                    HStack(spacing: 8) {
                                        Text(gathering.date.formatted(.dateTime.year().month().day()))
                                        if !gathering.place.isEmpty { Text(gathering.place) }
                                        Text("・出席\(gathering.attendees.count)名")
                                    }
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.inkSoft)
                                }
                            }
                            .listRowBackground(AppTheme.paperRaised)
                        }
                        .onDelete { offsets in
                            guard trialManager.canEdit else {
                                showingPurchaseSheet = true
                                return
                            }
                            for i in offsets { context.delete(gatherings[i]) }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(AppTheme.paper)
                }
            }
            .navigationTitle("集まり")
            .navigationDestination(for: Gathering.self) { gathering in
                GatheringDetailView(gathering: gathering)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        if trialManager.canEdit {
                            showingAddSheet = true
                        } else {
                            showingPurchaseSheet = true
                        }
                    } label: { Image(systemName: "plus") }
                        .accessibilityLabel("集まりを追加")
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                GatheringFormView()
            }
            .sheet(isPresented: $showingPurchaseSheet) {
                PurchaseSheet()
            }
        }
    }
}

struct GatheringFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(TrialManager.self) private var trialManager
    var gatheringToEdit: Gathering? = nil

    @State private var title = ""
    @State private var date = Date.now
    @State private var place = ""
    @State private var note = ""
    @State private var showingPurchaseSheet = false

    var body: some View {
        NavigationStack {
            Form {
                Section("集まり") {
                    TextField("例: 祖母の一周忌", text: $title)
                    DatePicker("日付", selection: $date, displayedComponents: .date)
                    TextField("場所", text: $place)
                }
                .listRowBackground(AppTheme.paperRaised)
                Section("メモ") {
                    TextField("メモ", text: $note, axis: .vertical).lineLimit(2...4)
                }
                .listRowBackground(AppTheme.paperRaised)
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.paper)
            .navigationTitle(gatheringToEdit == nil ? "集まりを追加" : "編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let g = gatheringToEdit {
                    title = g.title; date = g.date; place = g.place; note = g.note
                }
            }
            .sheet(isPresented: $showingPurchaseSheet) {
                PurchaseSheet()
            }
        }
    }

    private func save() {
        guard trialManager.canEdit else {
            showingPurchaseSheet = true
            return
        }
        if let g = gatheringToEdit {
            g.title = title; g.date = date; g.place = place; g.note = note
        } else {
            context.insert(Gathering(title: title, date: date, place: place, note: note))
        }
        dismiss()
    }
}

struct GatheringDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(TrialManager.self) private var trialManager
    @Bindable var gathering: Gathering
    @State private var showingAddAttendee = false
    @State private var showingPurchaseSheet = false

    @Query(sort: [SortDescriptor(\Person.kana), SortDescriptor(\Person.name)])
    private var allPersons: [Person]

    var body: some View {
        List {
            Section {
                if !gathering.place.isEmpty {
                    LabeledContent("場所", value: gathering.place)
                }
                LabeledContent("日付", value: gathering.date.formatted(.dateTime.year().month().day()))
                if !gathering.note.isEmpty {
                    Text(gathering.note).font(.subheadline).foregroundStyle(AppTheme.inkSoft)
                }
            }
            .listRowBackground(AppTheme.paperRaised)

            Section {
                ForEach(gathering.attendees) { person in
                    NavigationLink(value: person) {
                        HStack {
                            Text(person.name)
                            if !person.relationNote.isEmpty {
                                Text(person.relationNote)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.inkSoft)
                            }
                        }
                    }
                }
                .onDelete { offsets in
                    guard trialManager.canEdit else {
                        showingPurchaseSheet = true
                        return
                    }
                    for i in offsets {
                        let p = gathering.attendees[i]
                        gathering.attendees.removeAll { $0.persistentModelID == p.persistentModelID }
                    }
                }
                Button {
                    if trialManager.canEdit {
                        showingAddAttendee = true
                    } else {
                        showingPurchaseSheet = true
                    }
                } label: {
                    Label("出席者を追加", systemImage: "person.badge.plus")
                }
                .foregroundStyle(AppTheme.ai)
            } header: {
                Text("出席者(\(gathering.attendees.count)名)")
            }
            .listRowBackground(AppTheme.paperRaised)
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.paper)
        .navigationTitle(gathering.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Person.self) { person in
            PersonDetailView(person: person)
        }
        .sheet(isPresented: $showingAddAttendee) {
            AttendeePickerView(gathering: gathering, allPersons: allPersons)
        }
        .sheet(isPresented: $showingPurchaseSheet) {
            PurchaseSheet()
        }
    }
}

private struct AttendeePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(TrialManager.self) private var trialManager
    @Bindable var gathering: Gathering
    let allPersons: [Person]
    @State private var showingPurchaseSheet = false

    private var candidates: [Person] {
        allPersons.filter { p in !gathering.attendees.contains { $0.persistentModelID == p.persistentModelID } }
    }

    var body: some View {
        NavigationStack {
            List(candidates) { person in
                Button {
                    if trialManager.canEdit {
                        gathering.attendees.append(person)
                    } else {
                        showingPurchaseSheet = true
                    }
                } label: {
                    HStack {
                        Text(person.name).foregroundStyle(AppTheme.ink)
                        Spacer()
                        if gathering.attendees.contains(where: { $0.persistentModelID == person.persistentModelID }) {
                            Image(systemName: "checkmark").foregroundStyle(AppTheme.ai)
                        }
                    }
                }
                .listRowBackground(AppTheme.paperRaised)
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.paper)
            .navigationTitle("出席者を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } }
            }
            .sheet(isPresented: $showingPurchaseSheet) {
                PurchaseSheet()
            }
        }
    }
}
