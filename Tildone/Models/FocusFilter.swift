//
//  FocusFilter.swift
//  Tildone
//
//  Created by Diego Rivera on 5/1/24.
//

import AppIntents

struct FocusFilter: SetFocusFilterIntent {

    static var title: LocalizedStringResource = "Set contents visibility"
    static var description: IntentDescription = """
    Choose how to limit your notes' content visibility based on this Focus
    """
    
    var displayRepresentation: DisplayRepresentation {
        var title: String?
        switch (taskTextBlurred, noteMayStayBackground) {
        case (false, false):
            title = "Task text visible on a note that stays in the foreground"
        case (true, true):
            title = "Task text blurred on a note that may stay in the background"
        case (true, _):
            title = "Task text blurred"
        case (_, true):
            title = "Note may stay in the background"
        }
        return DisplayRepresentation(stringLiteral: title!)
    }
    
    @Parameter(title: "Task text blurred", default: false)
    var taskTextBlurred: Bool
    
    @Parameter(title: "Note may stay in the background", default: false)
    var noteMayStayBackground: Bool
    
    static var openAppWhenRun: Bool = false
    
    var appContext: FocusFilterAppContext {
        return FocusFilterAppContext()
    }
    
    func perform() async throws -> some IntentResult {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .visibility, object: (taskTextBlurred, noteMayStayBackground))
        }
        return .result()
    }
}
