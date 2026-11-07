import SwiftUI

struct ErrorBannerView: View {
    @EnvironmentObject private var settings: UserSettings
    let error: AppErrorMessage
    let onDismiss: () -> Void
    @State private var progress: CGFloat = 1

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(settings.theme.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text(error.title)
                    .font(Typography.ui(12, weight: .semibold))
                    .foregroundStyle(settings.theme.textPrimary)
                Text(error.message)
                    .font(Typography.ui(11.5))
                    .foregroundStyle(settings.theme.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            IconButton(systemName: "xmark", help: "Dismiss", size: 22, action: onDismiss)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .frame(maxWidth: 560)
        .glassSurface(RoundedRectangle(cornerRadius: 13, style: .continuous), tint: settings.theme.warning, elevated: true)
        .overlay(alignment: .bottomLeading) {
            GeometryReader { proxy in
                Capsule()
                    .fill(settings.theme.warning.opacity(0.6))
                    .frame(width: proxy.size.width * progress, height: 1.5)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 1)
        }
        .task(id: error.id) {
            progress = 1
            withAnimation(.linear(duration: 6)) { progress = 0 }
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            if !Task.isCancelled { onDismiss() }
        }
    }
}
