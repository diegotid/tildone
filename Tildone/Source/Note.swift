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
                Circle()
                    .frame(width: 20, height: 20, alignment: .center)
                    .background(Circle().foregroundColor(Color.clear))
                    .border(Color.gray, width: /*@START_MENU_TOKEN@*/1/*@END_MENU_TOKEN@*/)
                TextField("New task", text: $editedTask)
                    .font(.system(size: 16, weight: .regular, design: .default))
                    .textFieldStyle(PlainTextFieldStyle())
                    .foregroundColor(.primary)
                    .background(Color.clear)
                    .padding(15)
                Spacer()
            }
            Spacer()
        }
        .padding(10)
        .frame(minWidth: 100,
               idealWidth: 250,
               maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/,
               minHeight: 120,
               idealHeight: 300,
               maxHeight: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/,
               alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/)
    }
}


struct ContentView_Previews: PreviewProvider {
    
    static var previews: some View {
        
        Note()
    }
}
