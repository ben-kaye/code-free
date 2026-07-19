import SwiftUI

/// App Settings (⌘,). Appearance is first — window chrome preference.
struct SettingsView: View {
    @AppStorage(AppearancePreference.storageKey)
    private var appearanceRaw = AppearancePreference.system.rawValue

    private var appearance: Binding<AppearancePreference> {
        Binding(
            get: { AppearancePreference(rawValue: appearanceRaw) ?? .system },
            set: { appearanceRaw = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: appearance) {
                    ForEach(AppearancePreference.allCases) { pref in
                        Text(pref.title).tag(pref)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Appearance")
            } header: {
                Text("Appearance")
            } footer: {
                Text("Light and Dark override the system setting for this app only.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 360)
        .padding()
    }
}
