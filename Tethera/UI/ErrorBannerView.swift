import SwiftUI

struct ErrorBannerView: View {
    let error: AppErrorMessage
    let onDismiss: () -> Void
    @EnvironmentObject private var userSettings: UserSettings

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(userSettings.themeConfiguration.accentColor.color)
                .font(.system(size: 14, weight: .semibold))

            VStack(alignment: .leading, spacing: 2) {
                Text(error.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(userSettings.themeConfiguration.textColor.color)
                Text(error.message)
                    .font(.system(size: 11))
                    .foregroundColor(userSettings.themeConfiguration.textColor.color.opacity(0.7))
                    .lineLimit(2)
            }

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(userSettings.themeConfiguration.textColor.color.opacity(0.6))
                    .frame(width: 20, height: 20)
                    .background(
                        Circle()
                            .fill(userSettings.themeConfiguration.textColor.color.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(userSettings.themeConfiguration.accentColor.color.opacity(0.25), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 3)
    }
}
