//
//  DragPayloads.swift
//  AppPocket
//
//  Values carried by drag and drop.
//

import CoreTransferable
import Foundation
import UniformTypeIdentifiers

nonisolated extension UTType {
    /// Custom type so our own drags are unambiguous, and so a drop of plain
    /// text or a file URL from Finder can be told apart.
    ///
    /// `nonisolated` because `Transferable.transferRepresentation` is a
    /// nonisolated static requirement and reads these.
    static let appPocketApp = UTType(exportedAs: "com.liupeixin.AppPocket.app-reference")
    static let appPocketCategory = UTType(exportedAs: "com.liupeixin.AppPocket.category-reference")
}

/// One or more application identifiers being dragged onto a category.
nonisolated struct AppDragPayload: Codable, Hashable, Sendable, Transferable {
    let appIDs: [String]

    init(appIDs: [String]) {
        self.appIDs = appIDs
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .appPocketApp)
    }
}

/// A sidebar row being dragged to reorder the category list.
nonisolated struct CategoryDragPayload: Codable, Hashable, Sendable, Transferable {
    let categoryID: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .appPocketCategory)
    }
}
