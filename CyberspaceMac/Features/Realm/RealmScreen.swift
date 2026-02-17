import SwiftUI

struct RealmScreen: View {
    @EnvironmentObject private var appState: AppState

    @State private var realmName = "library-realm"
    @State private var host = "127.0.0.1"
    @State private var port = 7780

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Realm")
                .font(.title2.weight(.semibold))

            GroupBox("Status") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Status: \(appState.realmStatusValue.status)")
                    Text("Node: \(appState.realmStatusValue.nodeName)")
                    Text("Policy: \(appState.realmStatusValue.policy)")
                    Text("Members: \(appState.realmStatusValue.memberCount)")
                    Button("Refresh status") {
                        Task { await appState.refreshRealmStatus() }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Join Realm") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Realm name", text: $realmName)
                    TextField("Host", text: $host)
                    HStack {
                        Text("Port")
                        Spacer()
                        Stepper(value: $port, in: 1...65535) {
                            Text("\(port)")
                        }
                        .frame(width: 180)
                    }
                    Button("Join") {
                        Task {
                            await appState.joinRealm(name: realmName, host: host, port: port)
                            await appState.refreshRealmStatus()
                        }
                    }
                }
            }

            if let result = appState.realmJoinResult {
                Text("Join result: \(result.joined ? "success" : "failed") - \(result.message)")
                    .font(.caption)
                    .foregroundStyle(result.joined ? .green : .red)
            }

            Spacer()
        }
        .padding()
        .task {
            await appState.refreshRealmStatus()
        }
    }
}
