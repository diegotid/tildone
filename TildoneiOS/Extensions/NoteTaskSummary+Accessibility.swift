//
//  NoteTaskSummary+Accessibility.swift
//  Tildone
//
//  Created by Diego Rivera on 8/1/26.
//
import TildoneDomain

extension NoteTaskSummary {
    var accessibilityDescription: String {
        "\(completedCount) of \(totalCount) tasks completed"
    }
}
