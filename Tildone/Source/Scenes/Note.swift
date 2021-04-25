//
//  Note.swift
//  Tildone
//
//  Created by Diego on 24/4/21.
//

import SwiftUI

struct Note: View {
    
    @State private var editedTask = ""
        
    var body: some View {
        
        VStack {
            HStack {
                Checkbox()
                TextField(Copies.newTaskPlaceholder, text: $editedTask)
                    .font(.system(size: 16, weight: .regular, design: .default))
                    .textFieldStyle(PlainTextFieldStyle())
                    .foregroundColor(Color(.primaryFontColor))
                    .background(Color.clear)
                Spacer()
            }
            Spacer()
        }
        .padding()
        .colorScheme(.light)
        .frame(minWidth: Layout.minNoteWidth,
               idealWidth: Layout.defaultNoteWidth,
               maxWidth: .infinity,
               minHeight: Layout.minNoteHeight,
               idealHeight: Layout.defaultNoteHeight,
               maxHeight: .infinity,
               alignment: .center)
    }
}


struct ContentView_Previews: PreviewProvider {
    
    static var previews: some View {
        
        Note()
    }
}
