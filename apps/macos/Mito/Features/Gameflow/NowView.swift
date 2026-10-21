import SwiftUI

struct NowView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(app.gameflow.phaseTitle)
            } icon: {
                Image(systemName: app.gameflow.phaseSymbol)
            }
        }
    }
}

#Preview {
    NowView()
        .environment(AppModel(connection: DisconnectedLCUConnection()))
}
