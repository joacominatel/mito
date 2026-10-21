import SwiftUI

/// The "Ahora" destination: the shell's champ-select content while there is one, the phase
/// otherwise.
struct NowView<ChampSelect: View>: View {
    @Environment(AppModel.self) private var app

    let champSelect: ChampSelect?

    var body: some View {
        if let champSelect {
            champSelect
        } else {
            ContentUnavailableView {
                Label {
                    Text(app.gameflow.phaseTitle)
                } icon: {
                    Image(systemName: app.gameflow.phaseSymbol)
                }
            }
        }
    }
}

extension NowView where ChampSelect == EmptyView {
    init() {
        champSelect = nil
    }
}

#Preview {
    NowView()
        .environment(AppModel(connection: DisconnectedLCUConnection()))
}
