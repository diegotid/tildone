//
//  Topic.swift
//  Tildone
//
//  Created by Diego Rivera on 5/11/23.
//

import Foundation
import SwiftData

@Model
final class Topic {
    var title: String

    public init(title: String) {
        self.title = title
    }
}
