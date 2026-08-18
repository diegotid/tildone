//
//  MacSharedStoreBootstrapError.swift
//  Tildone
//

import Foundation

enum MacSharedStoreBootstrapError: Error, LocalizedError {
    case legacySourceMissing
    case unverifiedSharedStore
    case cloudAccountChanged

    var errorDescription: String? {
        switch self {
        case .legacySourceMissing:
            "The legacy Tildone store could not be found for migration."
        case .unverifiedSharedStore:
            "The shared Tildone store is not eligible for activation."
        case .cloudAccountChanged:
            "The iCloud account changed. Reopen Tildone to show the notes for the right account."
        }
    }
}
