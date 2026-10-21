import SwiftUI

struct OnboardingSettingsTab: View {
    var body: some View {
        Form {
            Text("Próximamente", tableName: "Onboarding")
        }
        .formStyle(.grouped)
    }
}

#Preview {
    OnboardingSettingsTab()
}
