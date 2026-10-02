# Drag-and-Drop Sorting — design sketch (superseded)

> ## ⚠️ 勘误 / Superseded — 2026-09-24
>
> **本文描述的设计没有实现。** 文中提出的 `DragState`、`DropTarget`、
> `DragAndDropManager` 三个类型在代码库中都不存在。
>
> 实际实现走的是 SwiftUI 原生的 `Transferable` + `.dropDestination`，
> 没有中间管理器，也**没有防抖**：
>
> - 载荷：`AppDragPayload`（一批应用 id）与 `CategoryDragPayload`（一个分类 id），
>   各自导出自己的 UTType，这样从 Finder 拖进来的文件或纯文本不会被误认。
> - 接收：侧栏每个智能分组与分类行都挂了 `.dropDestination(for: AppDragPayload.self)`，
>   分类行额外再挂一个 `CategoryDragPayload` 用于排序。
> - 落盘：落到 `LibraryStore.mutate`，它**同步**写文件。
>
> 防抖被去掉了，原因很直接：一个 `library.json` 只有几 KB，一次原子写的耗时
> 远低于 1 毫秒。为一次拖放引入 300 毫秒的延迟窗口，换来的是「应用崩溃时最后
> 一次拖放丢失」这种无法向用户解释的行为。写入足够便宜时，防抖是在制造问题。
>
> 下面保留的是原设计草案，作为历史记录。

---

## Overview

This document outlines the drag-and-drop sorting persistence logic for PocketLauncher's app organization system. The implementation provides smooth visual feedback during drag operations while ensuring efficient data persistence with debouncing.

## User Experience Flow

### 1. Drag Initiation
- User begins dragging an app cell
- Visual feedback: dragged cell becomes semi-transparent and slightly scaled down
- Other apps remain in their original positions
- Drop zones (categories and uncategorized area) become highlighted

### 2. During Drag
- Real-time visual placeholder shows where the app will be inserted
- Drop targets are highlighted when dragged item hovers over them
- Category cards show distinct visual state when they're valid drop targets

### 3. Drop Completion
- Immediate visual update: app appears in new position instantly
- Background: debounced persistence operation (300ms delay)
- If persistence fails, revert to previous state with user notification

## Technical Implementation

### Visual Feedback System

```swift
struct DragState {
    var draggedItem: AppDTO?
    var dropTarget: DropTarget?
    var insertionIndex: Int?
}

enum DropTarget {
    case category(UUID)
    case uncategorized
}
```

### Debounced Persistence

```swift
class DragAndDropManager: ObservableObject {
    private var persistenceTask: Task<Void, Never>?
    private let persistenceDelay: TimeInterval = 0.3
    
    func scheduleReorderPersistence(operation: @escaping () async throws -> Void) {
        // Cancel previous persistence task
        persistenceTask?.cancel()
        
        // Schedule new persistence operation
        persistenceTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(persistenceDelay * 1_000_000_000))
            
            guard !Task.isCancelled else { return }
            
            do {
                try await operation()
                await MainActor.run {
                    // Update UI to reflect successful persistence
                    self.markPersistenceComplete()
                }
            } catch {
                await MainActor.run {
                    // Revert UI changes and show error
                    self.handlePersistenceError(error)
                }
            }
        }
    }
    
    private func markPersistenceComplete() {
        // Update UI indicators, if any
    }
    
    private func handlePersistenceError(_ error: Error) {
        // Show error message and revert changes
        print("❌ Failed to persist reorder: \(error)")
    }
}
```

## Order Index Algorithm

### Problem: Efficient Insertion Between Items

When inserting an item between two existing items, we need to assign an `orderIndex` that maintains the correct sort order without requiring a full reindex of all items.

### Solution: Fractional Indexing

```swift
struct OrderIndexManager {
    
    /// Calculate order index for inserting item between two positions
    /// - Parameters:
    ///   - previousIndex: Order index of item before insertion point (nil if inserting at beginning)
    ///   - nextIndex: Order index of item after insertion point (nil if inserting at end)
    /// - Returns: New order index for the inserted item
    static func calculateInsertionIndex(
        previousIndex: Double?,
        nextIndex: Double?
    ) -> Double {
        switch (previousIndex, nextIndex) {
        case (nil, nil):
            // First item in empty list
            return 1000.0
            
        case (nil, let next?):
            // Insert at beginning
            return next / 2.0
            
        case (let prev?, nil):
            // Insert at end
            return prev + 1000.0
            
        case (let prev?, let next?):
            // Insert between two items
            let midpoint = (prev + next) / 2.0
            
            // Check if we have enough precision
            if abs(midpoint - prev) < 0.001 || abs(next - midpoint) < 0.001 {
                // Indices are too close together, trigger reindex
                return Double.nan // Special value indicating reindex needed
            }
            
            return midpoint
        }
    }
    
    /// Reindex all items in a collection to prevent precision issues
    /// - Parameter items: Items to reindex in their desired order
    /// - Returns: Dictionary mapping item IDs to new order indices
    static func reindexItems<T: Identifiable>(_ items: [T]) -> [T.ID: Double] {
        var result: [T.ID: Double] = [:]
        
        for (index, item) in items.enumerated() {
            result[item.id] = Double(index) * 1000.0
        }
        
        return result
    }
}
```

### Implementation Example

```swift
func applyReorder(categoryID: UUID?, newOrderedIDs: [UUID]) async throws {
    try await appRepository.performBackgroundTask { context in
        if let categoryID = categoryID {
            // Reorder within category
            try await self.reorderAppsInCategory(
                categoryID: categoryID,
                newOrderedIDs: newOrderedIDs,
                in: context
            )
        } else {
            // Reorder uncategorized apps
            try await self.reorderUncategorizedApps(
                newOrderedIDs: newOrderedIDs,
                in: context
            )
        }
        
        try context.save()
    }
}

private func reorderAppsInCategory(
    categoryID: UUID,
    newOrderedIDs: [UUID],
    in context: NSManagedObjectContext
) async throws {
    // Fetch category and its apps
    let categoryRequest = CategoryEntity.fetchRequest()
    categoryRequest.predicate = NSPredicate(format: "id == %@", categoryID as CVarArg)
    
    guard let category = try context.fetch(categoryRequest).first else {
        throw RepositoryError.categoryNotFound
    }
    
    // Fetch apps
    let appRequest = AppEntity.fetchRequest()
    appRequest.predicate = NSPredicate(format: "id IN %@", newOrderedIDs)
    let apps = try context.fetch(appRequest)
    
    // Create ordered array based on newOrderedIDs
    let orderedApps = newOrderedIDs.compactMap { id in
        apps.first { $0.id == id }
    }
    
    // Update category's apps ordered set
    category.apps = NSOrderedSet(array: orderedApps)
    
    // Calculate and assign new order indices
    let newIndices = OrderIndexManager.reindexItems(orderedApps)
    for app in orderedApps {
        if let newIndex = newIndices[app.id] {
            app.orderIndex = newIndex
        }
    }
}

private func reorderUncategorizedApps(
    newOrderedIDs: [UUID],
    in context: NSManagedObjectContext
) async throws {
    // Fetch uncategorized apps
    let appRequest = AppEntity.fetchRequest()
    appRequest.predicate = NSPredicate(
        format: "id IN %@ AND category == nil",
        newOrderedIDs
    )
    let apps = try context.fetch(appRequest)
    
    // Calculate and assign new order indices
    let newIndices = OrderIndexManager.reindexItems(
        newOrderedIDs.compactMap { id in
            apps.first { $0.id == id }
        }
    )
    
    for app in apps {
        if let newIndex = newIndices[app.id] {
            app.orderIndex = newIndex
        }
    }
}
```

## SwiftUI Drag and Drop Integration

### Drop Handler Implementation

```swift
struct AppGridView: View {
    @StateObject private var dragManager = DragAndDropManager()
    @State private var dragState = DragState()
    
    var body: some View {
        LazyVGrid(columns: gridColumns, spacing: 12) {
            ForEach(apps) { app in
                AppCellView(
                    app: app,
                    isDragged: dragState.draggedItem?.id == app.id
                )
                .onDrag {
                    dragState.draggedItem = app
                    return NSItemProvider(object: app.id.uuidString as NSString)
                }
                .onDrop(of: [.text], delegate: AppDropDelegate(
                    targetApp: app,
                    dragState: $dragState,
                    dragManager: dragManager,
                    onReorder: performReorder
                ))
            }
        }
    }
    
    private func performReorder(
        draggedAppId: UUID,
        targetAppId: UUID,
        insertBefore: Bool
    ) {
        // Immediate UI update
        updateLocalAppOrder(
            draggedId: draggedAppId,
            targetId: targetAppId,
            insertBefore: insertBefore
        )
        
        // Debounced persistence
        dragManager.scheduleReorderPersistence {
            try await self.persistAppOrder()
        }
    }
}
```

### Drop Delegate

```swift
struct AppDropDelegate: DropDelegate {
    let targetApp: AppDTO
    @Binding var dragState: DragState
    let dragManager: DragAndDropManager
    let onReorder: (UUID, UUID, Bool) -> Void
    
    func dropEntered(info: DropInfo) {
        guard let draggedApp = dragState.draggedItem,
              draggedApp.id != targetApp.id else { return }
        
        // Determine insertion position based on drop location
        let insertBefore = info.location.x < 36 // Half of cell width
        
        dragState.dropTarget = .app(targetApp.id)
        dragState.insertionIndex = apps.firstIndex { $0.id == targetApp.id }
    }
    
    func dropExited(info: DropInfo) {
        dragState.dropTarget = nil
        dragState.insertionIndex = nil
    }
    
    func performDrop(info: DropInfo) -> Bool {
        guard let draggedApp = dragState.draggedItem,
              let targetIndex = dragState.insertionIndex else { return false }
        
        let insertBefore = info.location.x < 36
        
        onReorder(draggedApp.id, targetApp.id, insertBefore)
        
        // Reset drag state
        dragState = DragState()
        
        return true
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
}
```

## Performance Optimizations

### 1. Efficient Reindexing
- Only reindex when order indices become too close (< 0.001 precision)
- Use background context for heavy operations
- Batch updates to minimize Core Data saves

### 2. Visual Performance
- Use `@State` for immediate UI updates
- Defer heavy persistence operations
- Cancel previous persistence tasks when new drag operations begin

### 3. Memory Management
- Weak references in delegate handlers
- Automatic cleanup of drag state on completion
- Efficient NSOrderedSet updates

## Error Handling

### Persistence Failures
```swift
private func handlePersistenceError(_ error: Error) {
    // Log error
    print("❌ Failed to persist app order: \(error)")
    
    // Revert UI to previous state
    Task { @MainActor in
        await self.revertToLastKnownState()
        
        // Show user notification
        self.showErrorAlert("Failed to save app order. Changes have been reverted.")
    }
}
```

### Data Consistency
- Validate app IDs exist before reordering
- Handle race conditions between multiple drag operations
- Maintain consistency between in-memory and persistent state

## Testing Strategy

### Unit Tests
- Test order index calculations with various scenarios
- Verify reindexing algorithm correctness
- Test persistence failure recovery

### UI Tests
- Verify drag and drop visual feedback
- Test category boundary detection
- Validate smooth animations during reorder operations

This implementation provides a robust, performant drag-and-drop experience while maintaining data consistency and providing excellent user feedback throughout the interaction.