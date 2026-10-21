import SwiftUI

/// The "Build" tab of the analysis panel (§20.2). A placeholder until its unit lands.
struct BuildTab: View {
    let subject: AnalysisSubject

    var body: some View {
        ContentUnavailableView {
            Label {
                Text("Build", tableName: "Build")
            } icon: {
                Image(systemName: "hammer")
            }
        } description: {
            Text("Runas, ítems, spells y habilidades: muy pronto.", tableName: "Build")
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }
}
