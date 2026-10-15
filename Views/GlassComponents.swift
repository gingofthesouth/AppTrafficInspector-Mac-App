import SwiftUI

struct GlassPanel<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(12)
            .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }
}

struct CaptureStatusPill: View {
    @ObservedObject private var status = TrafficListenerStatus.shared

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(status.isReady ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(status.summary)
                .lineLimit(1)
            Text(":\(AppTrafficConfiguration.portString)")
                .foregroundStyle(.secondary)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .capsule)
        .accessibilityIdentifier("capture-status")
    }
}

struct MethodBadge: View {
    let method: RequestMethod?

    var body: some View {
        Text(method?.rawValue ?? "—")
            .font(.caption2.weight(.bold))
            .foregroundStyle(method?.color() ?? .secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background((method?.color() ?? .secondary).opacity(0.13), in: Capsule())
    }
}
