import SwiftUI

struct KeepAwakeCustomView: View {
    let onStart: (Double) -> Void
    let onCancel: () -> Void

    @State private var minutes: Double = 60

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Keep Awake — Custom Duration").font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Duration")
                    Spacer()
                    Text(durationLabel(minutes))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(minWidth: 80, alignment: .trailing)
                }
                Slider(value: $minutes, in: 5...1440, step: 5)
                HStack {
                    Text("5 min")
                    Spacer()
                    Text("24 hr")
                }
                .font(.caption).foregroundStyle(.tertiary)
            }

            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Button("Start") { onStart(minutes) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 340)
    }
}

private func durationLabel(_ minutes: Double) -> String {
    let m = Int(minutes)
    if m < 60 { return "\(m) min" }
    let h = m / 60
    let rem = m % 60
    return rem > 0 ? "\(h) hr \(rem) min" : "\(h) hr"
}
