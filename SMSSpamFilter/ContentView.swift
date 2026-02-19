import SwiftUI

struct ContentView: View {

    private static let suiteName = "group.com.aaron.SMSSpamFilter"
    private static let thresholdKey = "spamThreshold"
    private static let totalFilteredKey = "totalFiltered"
    private static let spamBlockedKey = "spamBlocked"

    @State private var threshold: Double = 0.60
    @State private var totalFiltered: Int = 0
    @State private var spamBlocked: Int = 0

    private var hamAllowed: Int { totalFiltered - spamBlocked }

    private var defaults: UserDefaults? {
        UserDefaults(suiteName: Self.suiteName)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    statusCard
                    statsCard
                    thresholdCard
                    setupInstructions
                }
                .padding()
            }
            .navigationTitle("SMS Spam Filter")
            .onAppear(perform: loadStats)
        }
    }

    // MARK: - Status card

    private var statusCard: some View {
        HStack {
            Image(systemName: "checkmark.shield.fill")
                .font(.largeTitle)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 4) {
                Text("Filter Active")
                    .font(.headline)
                Text("On-device spam detection enabled")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Statistics card

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Statistics")
                .font(.headline)

            HStack(spacing: 16) {
                statBubble(value: totalFiltered, label: "Filtered", color: .blue)
                statBubble(value: spamBlocked, label: "Spam Blocked", color: .red)
                statBubble(value: hamAllowed, label: "Allowed", color: .green)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func statBubble(value: Int, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.title2.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Threshold slider

    private var thresholdCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Spam Threshold")
                    .font(.headline)
                Spacer()
                Text(String(format: "%.2f", threshold))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(value: $threshold, in: 0.30...0.95, step: 0.05) {
                Text("Threshold")
            } minimumValueLabel: {
                Text("Strict")
                    .font(.caption2)
            } maximumValueLabel: {
                Text("Lenient")
                    .font(.caption2)
            }
            .onChange(of: threshold) { _, newValue in
                defaults?.set(newValue, forKey: Self.thresholdKey)
            }

            Text("Lower values block more aggressively. Default: 0.60")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Setup instructions

    private var setupInstructions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Setup Instructions")
                .font(.headline)

            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1)")
                        .font(.caption.bold())
                        .frame(width: 24, height: 24)
                        .background(Color.accentColor.opacity(0.15), in: Circle())
                    Text(step)
                        .font(.subheadline)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private let steps = [
        "Open Settings on your iPhone",
        "Tap Messages",
        "Tap Unknown & Spam",
        "Enable Filter Unknown Senders",
        "Under SMS FILTERING, select SMSSpamFilter",
    ]

    // MARK: - Data loading

    private func loadStats() {
        guard let d = defaults else { return }
        totalFiltered = d.integer(forKey: Self.totalFilteredKey)
        spamBlocked = d.integer(forKey: Self.spamBlockedKey)
        let saved = d.double(forKey: Self.thresholdKey)
        threshold = saved > 0.01 ? saved : 0.60
    }
}

#Preview {
    ContentView()
}
