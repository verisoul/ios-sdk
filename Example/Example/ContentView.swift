//
//  ContentView.swift
//  DemoVerisoulSDK
//
//  Created by TOxIC on 12/12/2024.
//

import SwiftUI
import VerisoulSDK

struct ContentView: View {
    
    @State var sessionId = ""
    
    var body: some View {
        VStack {
            Text("Session id:").padding()
            Text(sessionId).contextMenu {
                Button(action: {
                    UIPasteboard.general.string = sessionId
                }) {
                    Text("Copy to clipboard")
                    Image(systemName: "doc.on.doc")
                }
            }.padding()
            
        }.onAppear() {
            Task {
                let value = try await Verisoul.shared.session()
                self.sessionId = value
            }
        }
    }
}

#Preview {
    ContentView()
}
