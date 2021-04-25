//
//  Note.swift
//  Tildone
//
//  Created by Diego on 24/4/21.
//

import SwiftUI

struct Note: View {
    
    @State private var editedTask = ""
    @State private var editedTopic = ""

    var body: some View {
        
        ScrollView(.vertical) {
            VStack(spacing: 6) {
                ForEach((1..<2)) { _ in
                    TextField(Copies.newTopicPlaceholder, text: $editedTopic)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(Color(.primaryFontColor))
                        .background(Color.clear)
                        .padding(.top, 15)
                    ForEach((1..<4)) { _ in
                        HStack(spacing: 8) {
                            Checkbox()
                            TextField(Copies.newTaskPlaceholder, text: $editedTask)
                                .textFieldStyle(PlainTextFieldStyle())
                                .foregroundColor(Color(.primaryFontColor))
                                .background(Color.clear)
                            Spacer()
                        }.padding(.leading, 2)
                    }
                }
                Spacer()
            }
        }
        .padding(.top, 0)
        .padding(.trailing, 5)
        .padding(.leading, 20)
        .padding(.bottom, 20)
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
