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

    @State var result = ""

    var body: some View {
        VStack {
            Text("Debugger attached \(DebuggerChecker.amIDebugged())").padding()
            Text("Session id:").padding()
            Text(Bundle.main.bundleIdentifier ?? "")

            Text(sessionId).contextMenu {
                Button(action: {
                    UIPasteboard.general.string = sessionId
                }) {
                    Text("Copy to clipboard")
                    Image(systemName: "doc.on.doc")
                }
            }.padding()

            Button(action: {
                Task {
                    do {
                        Verisoul.shared.reinitialize()

                        let value = try await Verisoul.shared.session()
                        self.sessionId = value
                    }catch{
                        self.sessionId = "error \(error)"

                    }
                }

                    }) {
                        Text("reInitialize")
                            .padding()
                            .cornerRadius(10)
                    }

        }.onAppear() {
            Task {
                do {
                    let value = try await Verisoul.shared.session()
                    self.sessionId = value
                }catch{
                    self.sessionId = "error \(error)"

                }
            }
        }
    }
}

#Preview {
    ContentView()
}
