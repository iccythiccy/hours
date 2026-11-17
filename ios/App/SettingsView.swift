import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var settings = Settings()
    @State private var restoreText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. Mike", text: $settings.name)
                        .textInputAutocapitalization(.words)
                } header: { Text("Client name (for the button)") }

                Section {
                    TextField("e.g. 941-555-0123", text: $settings.phone)
                        .keyboardType(.phonePad)
                } header: { Text("Client's mobile number") }
                  footer: { Text("Stored only on this phone. Used to open Messages with your hours already typed in.") }

                Section {
                    Toggle("Include break times in the text", isOn: $settings.showBrk)
                }

                Section {
                    Text(m.backupSummary).foregroundStyle(.secondary)
                    Button("Copy backup") { m.copyBackup() }
                    TextEditor(text: $restoreText)
                        .frame(minHeight: 70)
                        .font(.footnote)
                        .overlay(alignment: .topLeading) {
                            if restoreText.isEmpty {
                                Text("To restore: paste a backup here (from this app or the web app), then tap Restore.")
                                    .font(.footnote).foregroundStyle(.tertiary).padding(.top, 8).padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                        }
                    Button("Restore") { if m.restore(restoreText) { restoreText = "" } }
                        .disabled(restoreText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: { Text("Backup") }
                  footer: { Text("Copy a backup into Notes now and then. Moving from the web app: tap Copy backup there, then paste it here.") }

                Section {
                    LabeledContent("Version", value: AppModel.version)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        settings.name = settings.name.trimmingCharacters(in: .whitespaces)
                        settings.phone = settings.phone.trimmingCharacters(in: .whitespaces)
                        m.updateSettings(settings)
                        dismiss()
                    }.fontWeight(.semibold)
                }
            }
            .onAppear { settings = m.state.settings }
        }
    }
}
