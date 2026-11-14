import SwiftUI

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.cardBackground, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}

extension View {
    func cardStyle() -> some View { modifier(CardStyle()) }
}

/// Selectable filter chip. Selection is conveyed by checkmark + trait, not colour alone.
struct ChipView: View {
    let title: String
    var systemImage: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                if isSelected {
                    Image(systemName: "checkmark").font(.caption.weight(.bold))
                } else if let systemImage {
                    Image(systemName: systemImage).font(.caption)
                }
                Text(title).font(.subheadline.weight(isSelected ? .semibold : .regular))
            }
            .padding(.horizontal, Spacing.m)
            .frame(minHeight: Layout.minTouchTarget)
            .background(isSelected ? AnyShapeStyle(Palette.accent.opacity(0.2)) : AnyShapeStyle(Palette.chipBackground),
                        in: Capsule())
            .overlay(Capsule().strokeBorder(isSelected ? Palette.accent : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Label marking AI-generated material. Icon + text so it does not rely on colour.
struct GeneratedContentBadge: View {
    var body: some View {
        Label("AI-generated", systemImage: "wand.and.stars")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Palette.generatedContent)
            .accessibilityLabel("AI-generated content")
    }
}

/// Label marking bundled sample content so it is never mistaken for live news.
struct SampleDataBadge: View {
    var body: some View {
        Label("Sample data", systemImage: "testtube.2")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Palette.sample)
            .accessibilityLabel("Sample data, not live news")
    }
}

/// Shimmer-free skeleton placeholder (respects Reduce Motion by not animating).
struct SkeletonCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            RoundedRectangle(cornerRadius: 4).frame(height: 18)
            RoundedRectangle(cornerRadius: 4).frame(width: 220, height: 18)
            RoundedRectangle(cornerRadius: 4).frame(width: 140, height: 12)
        }
        .foregroundStyle(Palette.chipBackground)
        .cardStyle()
        .accessibilityHidden(true)
    }
}

struct LoadingListView: View {
    var count = 4
    var body: some View {
        VStack(spacing: Spacing.m) {
            ForEach(0..<count, id: \.self) { _ in SkeletonCard() }
        }
        .padding(.horizontal, Spacing.l)
        .accessibilityElement()
        .accessibilityLabel("Loading")
        .accessibilityIdentifier("loading")
    }
}

/// Shared error / offline / empty state with an actionable retry.
struct StateMessageView: View {
    let title: String
    let message: String
    let systemImage: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("state.action")
            }
        }
    }
}
