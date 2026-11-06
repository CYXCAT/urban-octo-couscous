import SwiftUI

/// Compact pill showing network type and server reachability. Tap to re-check now.
struct NetworkStatusView: View {
    @Environment(NetworkStatusMonitor.self) private var monitor
    @State private var showingDetails = false

    var body: some View {
        Button {
            showingDetails = true
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Image(systemName: monitor.interface.symbol)
                    .font(.caption)
                Text(monitor.summary)
                    .font(.caption)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.12), in: Capsule())
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Network status: \(monitor.summary)")
        .animation(.default, value: monitor.summary)
        .popover(isPresented: $showingDetails) {
            details
                .presentationCompactAdaptation(.popover)
        }
    }

    private var color: Color {
        switch monitor.overall {
        case .good: .green
        case .degraded: .orange
        case .offline: .red
        case .checking: .gray
        }
    }

    private var serverText: String {
        switch monitor.server {
        case .checking: "Checking…"
        case .online: "Online"
        case .unreachable: "Unreachable"
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connection").font(.headline)
            LabeledContent("Network", value: monitor.interface.label)
            LabeledContent("Server", value: serverText)
            if let latency = monitor.latencyText {
                LabeledContent("Latency", value: latency)
            }
            if monitor.isConstrained {
                LabeledContent("Low Data Mode", value: "On")
            }
            if monitor.isExpensive {
                LabeledContent("Metered", value: "Yes")
            }
            if let lastChecked = monitor.lastChecked {
                LabeledContent("Checked") {
                    Text(lastChecked, style: .relative) + Text(" ago")
                }
            }
            Button("Check Now") {
                Task { await monitor.checkServer() }
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
        .font(.subheadline)
        .padding()
        .frame(minWidth: 240)
    }
}

#Preview {
    NetworkStatusView()
        .environment(NetworkStatusMonitor())
}
