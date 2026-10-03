import BibleAI
import BibleDomain
import SwiftUI

/// The Bible chat panel: a conversation answered from King James passages,
/// with checked citations as links, an attached-verse chip, saved chats and
/// New Chat.
struct BibleChatView: View {
    let model: BibleChatModel
    let engine: AIEngineModel
    let semanticSearch: SemanticSearchModel
    /// The in-panel header (Mac, iPad inspector). Without it the title and
    /// buttons go in the enclosing navigation bar (iPhone Chat tab).
    var showsHeader = true
    /// Opens a verse in the reader (citations and Sources).
    let open: (BibleReference) -> Void

    @State private var text = ""
    @State private var isShowingHistory = false
    /// Answers whose Sources list is expanded.
    @State private var expandedSources: Set<UUID> = []

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var title: String {
        model.conversation.title.isEmpty ? String(localized: "Bible Chat") : model.conversation.title
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
                header
                Divider()
            }
            if engine.choice.isUsable {
                thread
                Divider()
                composer
            } else {
                unavailableContent
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            guard let reference = CitationLink.reference(from: url) else { return .systemAction }
            open(reference)
            return .handled
        })
        .task { await model.loadSummaries() }
        #if os(iOS)
        .modifier(NavigationBarChrome(isActive: !showsHeader, title: title) {
            historyButton
            newChatButton
        })
        #endif
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(title)
                .font(.headline)
                .lineLimit(1)
                .accessibilityIdentifier("chatTitle")
            Spacer()
            historyButton
            newChatButton
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var historyButton: some View {
        Button {
            isShowingHistory = true
        } label: {
            Label("Chats", systemImage: "clock.arrow.circlepath")
        }
        .help("Saved chats")
        .accessibilityIdentifier("chatHistoryButton")
        #if os(iOS)
        // A popover would be a sheet on iPhone anyway; this one has a title
        // and Done, and stops at half height.
        .sheet(isPresented: $isShowingHistory) {
            NavigationStack {
                ChatHistoryView(model: model, open: openSaved)
                    .navigationTitle("Chats")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { isShowingHistory = false }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
        #else
        .popover(isPresented: $isShowingHistory) {
            ChatHistoryView(model: model, open: openSaved)
        }
        #endif
    }

    private var newChatButton: some View {
        Button {
            model.newChat()
            text = ""
        } label: {
            Label("New Chat", systemImage: "square.and.pencil")
        }
        .help("New chat")
        .keyboardShortcut("n", modifiers: [.command, .shift])
        .disabled(model.conversation.messages.isEmpty)
        .accessibilityIdentifier("newChatButton")
    }

    private func openSaved(_ id: UUID) {
        isShowingHistory = false
        Task { await model.open(id) }
    }

    // MARK: - Thread

    private var thread: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if model.conversation.messages.isEmpty {
                        emptyState
                    }
                    ForEach(model.conversation.messages) { message in
                        switch message.role {
                        case .user:
                            userBubble(message)
                        case .assistant:
                            answer(message)
                        }
                    }
                    Color.clear.frame(height: 1).id(Self.bottomID)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            #if os(iOS)
            .scrollDismissesKeyboard(.interactively)
            #endif
            .onChange(of: model.conversation.messages.last?.text) { _, _ in
                proxy.scrollTo(Self.bottomID, anchor: .bottom)
            }
            .onChange(of: model.conversation.id) { _, _ in
                proxy.scrollTo(Self.bottomID, anchor: .bottom)
            }
            .onChange(of: expandedSources) { old, new in
                // Sources opened on the latest answer would otherwise
                // unfold below the visible area.
                guard let last = model.conversation.messages.last?.id,
                      new.contains(last), !old.contains(last)
                else { return }
                withAnimation { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
            }
        }
    }

    private static let bottomID = "chatBottom"

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ask anything about the Bible, in any language. Answers cite verses from the version you’re reading, which you can open. Select a verse in the reader to ask about it.")
                .foregroundStyle(.secondary)
            if semanticSearch.isOffered, !semanticSearch.isInstalled {
                Text("Find answers by meaning and in any language with an optional on-device search model.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SemanticSearchControls(model: semanticSearch)
                    .controlSize(.small)
            }
        }
    }

    private func userBubble(_ message: ChatMessage) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            if let verse = message.attachedVerse {
                Button {
                    if let reference = verse.reference { open(reference) }
                } label: {
                    Label(verse.title, systemImage: "text.quote")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
            Text(message.text)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("chatQuestion")
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    @ViewBuilder
    private func answer(_ message: ChatMessage) -> some View {
        let isInFlight = model.isAnswering && message.id == model.conversation.messages.last?.id
        VStack(alignment: .leading, spacing: 8) {
            if isInFlight, model.phase == .searching {
                ProgressView("Searching the Bible…")
                    .controlSize(.small)
            } else {
                Label("Generated answer — not Scripture", systemImage: "sparkles")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("generatedAnswerLabel")

                let citations = model.citations[message.id] ?? []
                Text(CitationText.attributed(message.text, citations: citations))
                    .textSelection(.enabled)
                    .accessibilityIdentifier("chatAnswer")

                if isInFlight {
                    ProgressView().controlSize(.small)
                } else {
                    switch message.status {
                    case .completed:
                        EmptyView()
                    case .stopped:
                        Text("Stopped.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case let .failed(error):
                        Text(error)
                            .foregroundStyle(.red)
                    }
                    if CitationText.hasUnverified(citations) {
                        Text("Orange citations were not among the passages used for this answer; struck-through ones were not found in the Bible.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    sources(for: message)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func sources(for message: ChatMessage) -> some View {
        if !message.sources.isEmpty {
            let isExpanded = expandedSources.contains(message.id)
            Button {
                if isExpanded {
                    expandedSources.remove(message.id)
                } else {
                    expandedSources.insert(message.id)
                }
            } label: {
                Label("Sources (\(message.sources.count))", systemImage: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption.bold())
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("chatSources")

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.usedSemanticSearch ? "Found by keywords and meaning." : "Found by keywords.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(message.sources) { source in
                        Button {
                            if let reference = source.reference { open(reference) }
                        } label: {
                            Label(source.title, systemImage: "book")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("chatSource-\(source.bookID)-\(source.chapter)-\(source.firstVerse)")
                    }
                }
                .padding(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let attached = model.attachedVerse {
                HStack(spacing: 6) {
                    Label(attached.title, systemImage: "text.quote")
                        .accessibilityIdentifier("attachedVerseChip")
                    Button {
                        model.detach()
                    } label: {
                        Label("Remove \(attached.title)", systemImage: "xmark.circle.fill")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("removeAttachedVerseButton")
                }
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.quaternary, in: Capsule())
            }

            HStack(alignment: .bottom) {
                TextField(
                    model.attachedVerse == nil ? "Ask about the Bible" : "Ask about this verse",
                    text: $text,
                    axis: .vertical
                )
                .lineLimit(1...5)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)
                .accessibilityIdentifier("chatInputField")

                if model.isAnswering {
                    Button("Stop") { model.stop() }
                        .accessibilityIdentifier("chatStopButton")
                } else {
                    Button("Send", action: submit)
                        .disabled(trimmed.isEmpty)
                        .keyboardShortcut(.return, modifiers: .command)
                        .accessibilityIdentifier("chatSendButton")
                }
            }
        }
        .padding()
    }

    private func submit() {
        guard !trimmed.isEmpty, !model.isAnswering else { return }
        model.send(trimmed)
        text = ""
    }

    // MARK: - Unavailable

    private var unavailableContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(engine.statusMessage)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("aiUnavailableMessage")
            if engine.tier != nil {
                ModelDownloadControls(engine: engine)
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Saved chats, newest first; tap to open, delete with the trash button or a swipe.
struct ChatHistoryView: View {
    let model: BibleChatModel
    let open: (UUID) -> Void

    var body: some View {
        Group {
            if model.summaries.isEmpty {
                ContentUnavailableView("No Saved Chats", systemImage: "bubble.left.and.bubble.right")
            } else {
                List {
                    ForEach(model.summaries) { summary in
                        HStack {
                            Button {
                                open(summary.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(summary.title.isEmpty ? String(localized: "Untitled chat") : summary.title)
                                        .lineLimit(2)
                                    Text(summary.updatedAt, format: .relative(presentation: .named))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("chatHistoryRow")

                            Button(role: .destructive) {
                                Task { await model.delete(summary.id) }
                            } label: {
                                Label("Delete Chat", systemImage: "trash")
                                    .labelStyle(.iconOnly)
                            }
                            .buttonStyle(.borderless)
                            .help("Delete chat")
                            .accessibilityIdentifier("deleteChatButton")
                        }
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { model.summaries[$0].id }
                        Task { for id in ids { await model.delete(id) } }
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 280, minHeight: 320)
        #endif
        .task { await model.loadSummaries() }
    }
}

#if os(iOS)
/// Puts the chat's title and buttons in the navigation bar when the panel
/// has no header of its own.
private struct NavigationBarChrome<Buttons: View>: ViewModifier {
    let isActive: Bool
    let title: String
    @ViewBuilder let buttons: () -> Buttons

    func body(content: Content) -> some View {
        if isActive {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        buttons()
                    }
                }
        } else {
            content
        }
    }
}
#endif
