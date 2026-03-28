import SwiftUI

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var settings: AppSettings = AppSettings()
    @State private var saved = false

    var body: some View {
        Form {
            Section("Parental PIN") {
                TextField("PIN (4-6 digits)", text: $settings.pin)
                    .keyboardType(.numberPad)
            }

            Section("Daily Watch Limit") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(settings.dailyLimitMinutes.map { "\($0) min" } ?? "No limit")
                            .font(.headline)
                        Spacer()
                        Button("No Limit") { settings.dailyLimitMinutes = nil }
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }

                    if let limit = settings.dailyLimitMinutes {
                        Slider(
                            value: Binding(
                                get: { Double(limit) },
                                set: { settings.dailyLimitMinutes = Int($0) }
                            ),
                            in: 15...240, step: 15
                        )
                    }

                    HStack(spacing: 8) {
                        ForEach([15, 60, 120, 240], id: \.self) { min in
                            Button {
                                settings.dailyLimitMinutes = min
                            } label: {
                                Text(min < 60 ? "\(min)m" : "\(min/60)h")
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(settings.dailyLimitMinutes == min
                                        ? Color.blue : Color.secondary.opacity(0.15))
                                    .foregroundStyle(settings.dailyLimitMinutes == min ? .white : .primary)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }

                let todayMin = store.todayWatchSeconds / 60
                LabeledContent("Today's Watch Time", value: "\(todayMin) min")
                    .foregroundStyle(.secondary)
            }

            Section("Allowed Hours") {
                HStack {
                    Text("Start")
                    Spacer()
                    TextField("HH:mm", text: Binding(
                        get: { settings.allowedStartTime ?? "" },
                        set: { settings.allowedStartTime = $0.isEmpty ? nil : $0 }
                    ))
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numbersAndPunctuation)
                    .frame(width: 80)
                }
                HStack {
                    Text("End")
                    Spacer()
                    TextField("HH:mm", text: Binding(
                        get: { settings.allowedEndTime ?? "" },
                        set: { settings.allowedEndTime = $0.isEmpty ? nil : $0 }
                    ))
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numbersAndPunctuation)
                    .frame(width: 80)
                }
                Text("Leave blank for no restriction")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Volume Limiter") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Max Volume")
                        Spacer()
                        Text("\(Int(settings.maxVolume * 100))%")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.maxVolume, in: 0.1...1.0, step: 0.05)
                }
            }

            Section {
                Button {
                    store.updateSettings(settings)
                    saved = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
                } label: {
                    HStack {
                        Spacer()
                        if saved {
                            Label("Saved", systemImage: "checkmark")
                                .foregroundStyle(.green)
                        } else {
                            Text("Save Settings")
                        }
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("Settings")
        .onAppear { settings = store.settings }
    }
}
