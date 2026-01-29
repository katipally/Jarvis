import SwiftUI

struct RayModeView: View {
    @StateObject private var viewModel = RayModeViewModel()
    @FocusState private var isSearchFocused: Bool
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 0) {
            // Search Bar
            searchBar
            
            // Category Pills
            categoryPills
            
            Divider()
                .opacity(0.3)
            
            // Results Area
            if viewModel.searchText.isEmpty {
                emptyStateView
            } else {
                resultsListView
            }
        }
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear {
            isSearchFocused = true
        }
        .background(
            KeyEventHandler { event in
                handleKeyDown(event)
            }
            .frame(width: 0, height: 0)
        )
    }
    
    // MARK: - Search Bar
    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
            
            TextField("Search apps, calculate, find emoji...", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .focused($isSearchFocused)
                .onSubmit {
                    viewModel.executeSelected()
                }
            
            if !viewModel.searchText.isEmpty {
                Button(action: { viewModel.searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            // Keyboard shortcut hint
            Text("⌘3")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.1)))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
    
    // MARK: - Category Pills
    private var categoryPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(RayCategory.allCases) { category in
                    CategoryPill(
                        category: category,
                        isSelected: viewModel.activeCategory == category,
                        action: {
                            viewModel.activeCategory = category
                            Task { @MainActor in
                                await viewModel.performSearch()
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Quick Actions
                quickActionsSection
                
                // Running Apps
                if !AppSearchManager.shared.getRunningApps().isEmpty {
                    runningAppsSection
                }
                
                // Upcoming Events
                if !viewModel.upcomingEvents.isEmpty {
                    calendarSection
                }
                
                // Clipboard History
                if !viewModel.clipboardHistory.isEmpty {
                    clipboardSection
                }
            }
            .padding(12)
        }
    }
    
    // MARK: - Quick Actions Section
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Actions")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                QuickActionButton(icon: "rectangle.lefthalf.filled", title: "Left", color: .blue) {
                    viewModel.snapWindowLeft()
                }
                QuickActionButton(icon: "rectangle.righthalf.filled", title: "Right", color: .blue) {
                    viewModel.snapWindowRight()
                }
                QuickActionButton(icon: "rectangle.topthird.inset.filled", title: "Top", color: .green) {
                    viewModel.snapWindowTop()
                }
                QuickActionButton(icon: "arrow.up.left.and.arrow.down.right", title: "Max", color: .purple) {
                    viewModel.maximizeWindow()
                }
            }
        }
    }
    
    // MARK: - Running Apps Section
    private var runningAppsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Running Apps")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(AppSearchManager.shared.getRunningApps().prefix(8)) { app in
                        let appCopy = app
                        RunningAppItem(app: app) {
                            Task { @MainActor in
                                _ = await AppSearchManager.shared.launchApp(appCopy)
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Calendar Section
    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Upcoming Events")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Open Calendar") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Calendar")!)
                }
                .font(.system(size: 10))
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
            }
            .padding(.horizontal, 4)
            
            VStack(spacing: 4) {
                ForEach(viewModel.upcomingEvents.prefix(3)) { event in
                    CalendarEventRow(event: event)
                }
            }
        }
    }
    
    // MARK: - Clipboard Section
    private var clipboardSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Clipboard History")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("⌘⇧V")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 4)
            
            VStack(spacing: 2) {
                ForEach(viewModel.clipboardHistory.prefix(3)) { item in
                    ClipboardHistoryRow(item: item) {
                        viewModel.pasteFromHistory(item)
                    }
                }
            }
        }
    }
    
    // MARK: - Results List
    private var resultsListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(viewModel.results.enumerated()), id: \.element.id) { index, result in
                        RayModeResultRow(
                            result: result,
                            isSelected: index == viewModel.selectedIndex
                        )
                        .id(index)
                        .onTapGesture {
                            viewModel.selectedIndex = index
                            viewModel.executeSelected()
                        }
                    }
                }
                .padding(8)
            }
            .onChange(of: viewModel.selectedIndex) { newIndex in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
    }
    
    // MARK: - Handle Key Events
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 125: // Down arrow
            viewModel.selectNext()
            return true
        case 126: // Up arrow
            viewModel.selectPrevious()
            return true
        case 36: // Return
            viewModel.executeSelected()
            return true
        case 53: // Escape
            viewModel.searchText = ""
            return true
        default:
            return false
        }
    }
}

// MARK: - Key Event Handler View Modifier
struct KeyEventHandler: NSViewRepresentable {
    let onKeyDown: (NSEvent) -> Bool
    
    func makeNSView(context: Context) -> KeyEventView {
        let view = KeyEventView()
        view.onKeyDown = onKeyDown
        return view
    }
    
    func updateNSView(_ nsView: KeyEventView, context: Context) {
        nsView.onKeyDown = onKeyDown
    }
}

class KeyEventView: NSView {
    var onKeyDown: ((NSEvent) -> Bool)?
    
    override var acceptsFirstResponder: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) != true {
            super.keyDown(with: event)
        }
    }
}

// MARK: - Category Pill
struct CategoryPill: View {
    let category: RayCategory
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: category.icon)
                    .font(.system(size: 10))
                Text(category.rawValue)
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? Color.blue.opacity(0.8) : Color.white.opacity(0.1))
            )
            .foregroundStyle(isSelected ? .white : .white.opacity(0.7))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - RayMode Result Row (for new RayResult type)
struct RayModeResultRow: View {
    let result: RayResult
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            if let appIcon = result.appIcon {
                Image(nsImage: appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
            } else if result.category == .emoji {
                Text(result.title)
                    .font(.system(size: 24))
                    .frame(width: 32, height: 32)
            } else if let icon = result.icon {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(result.category.color.opacity(0.2))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundStyle(result.category.color)
                }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(result.category.color.opacity(0.2))
                        .frame(width: 32, height: 32)
                    Image(systemName: result.category.icon)
                        .font(.system(size: 14))
                        .foregroundStyle(result.category.color)
                }
            }
            
            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(result.category == .emoji ? result.subtitle : result.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                
                if result.category != .emoji {
                    Text(result.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Category badge
            Text(result.category.rawValue)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(result.category.color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(result.category.color.opacity(0.15)))
            
            // Return hint when selected
            if isSelected {
                Image(systemName: "return")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.blue.opacity(0.3) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Quick Action Button
struct QuickActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(color)
                
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Running App Item
struct RunningAppItem: View {
    let app: SearchableApp
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(nsImage: app.icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 36, height: 36)
                
                Text(app.name)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                    .frame(width: 50)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Calendar Event Row
struct CalendarEventRow: View {
    let event: CalendarEvent
    
    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(event.calendarColor)
                .frame(width: 4, height: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                
                Text("\(event.dateString) • \(event.timeString)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.05))
        )
    }
}

// MARK: - Clipboard History Row
struct ClipboardHistoryRow: View {
    let item: ClipboardItem
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 12))
                    .foregroundStyle(.purple)
                    .frame(width: 20)
                
                Text(item.preview)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .foregroundStyle(.white.opacity(0.8))
                
                Spacer()
                
                Text(item.timeAgo)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview
#Preview {
    RayModeView()
        .frame(width: 380, height: 520)
        .background(Color.black)
}
