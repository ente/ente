import SwiftUI

struct KnowledgeSettingsView: View {
    @ObservedObject var store: KnowledgeStore
    @State private var attributionPack: KnowledgePackState?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: EnsuSpacing.md) {
                ForEach(store.packs) { pack in
                    packCard(pack)
                }
            }
            .padding(EnsuSpacing.lg)
        }
        .background(EnsuColor.backgroundBase)
        .navigationTitle("Ensu Packs")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $attributionPack) { pack in
            PackAttributionSheet(config: pack.config)
        }
    }

    @ViewBuilder
    private func packCard(_ pack: KnowledgePackState) -> some View {
        let attribution = pack.config.attribution
        VStack(alignment: .leading, spacing: EnsuSpacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: EnsuSpacing.xs) {
                    Text(pack.config.label)
                        .font(EnsuTypography.large)
                        .foregroundStyle(EnsuColor.textPrimary)
                    HStack(spacing: EnsuSpacing.xs) {
                        Text(pack.config.downloadSizeBytes.formattedFileSize)
                            .font(EnsuTypography.mini)
                            .foregroundStyle(EnsuColor.textMuted)
                        Text("·")
                            .font(EnsuTypography.mini)
                            .foregroundStyle(EnsuColor.textMuted)
                        Button {
                            attributionPack = pack
                        } label: {
                            HStack(spacing: EnsuSpacing.xs) {
                                Text(attribution.licenseLabel)
                                    .font(EnsuTypography.mini)
                                Image(systemName: "info.circle")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundStyle(EnsuColor.accent)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("View attribution for \(pack.config.label)")
                    }
                }
                Spacer()
                if pack.activeIdentity != nil && !pack.isMutating {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { pack.enabled },
                            set: { store.setEnabled(stableId: pack.id, enabled: $0) }
                        )
                    )
                    .labelsHidden()
                } else if store.downloadsAllowed && pack.status == .download && !pack.isMutating {
                    Button {
                        store.downloadOrUpdate(stableId: pack.id)
                    } label: {
                        Text("Download")
                            .font(EnsuTypography.small)
                            .padding(.horizontal, EnsuSpacing.xs)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(EnsuColor.accent)
                }
            }

            if pack.isMutating {
                ProgressView(value: Double(pack.progressPercent ?? 0), total: 100)
                    .tint(EnsuColor.action)
                Text(pack.progressLabel ?? "Downloading...")
                    .font(EnsuTypography.small)
                    .foregroundStyle(EnsuColor.textMuted)
                Button("Cancel") {
                    store.cancel(stableId: pack.id)
                }
            } else if store.downloadsAllowed && pack.status == .updateAvailable {
                Button {
                    store.downloadOrUpdate(stableId: pack.id)
                } label: {
                    Text("Update")
                        .font(EnsuTypography.small)
                        .padding(.horizontal, EnsuSpacing.xs)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(EnsuColor.accent)
            }

            if let error = pack.errorMessage {
                Text(error)
                    .font(EnsuTypography.small)
                    .foregroundStyle(EnsuColor.error)
            }
        }
        .padding(EnsuSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EnsuColor.fillFaint)
        .clipShape(RoundedRectangle(cornerRadius: EnsuCornerRadius.card, style: .continuous))
    }
}

private struct PackAttributionSheet: View {
    let config: KnowledgeDatasetConfig
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let attribution = config.attribution
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: EnsuSpacing.sm) {
                    Text(config.label)
                        .font(EnsuTypography.large)
                        .foregroundStyle(EnsuColor.textPrimary)

                    Divider()

                    Text("From \(attribution.credit)")
                        .font(EnsuTypography.body)
                        .foregroundStyle(EnsuColor.textPrimary)

                    Text(attribution.modificationNotice)
                        .font(EnsuTypography.body)
                        .foregroundStyle(EnsuColor.textPrimary)

                    HStack(spacing: EnsuSpacing.md) {
                        Link(destination: URL(string: attribution.publicPackUrl)!) {
                            Label("Source", systemImage: "arrow.up.right.square")
                        }
                        Link(destination: URL(string: attribution.licenseUrl)!) {
                            Label("License", systemImage: "doc.text")
                        }
                    }
                    .font(EnsuTypography.mini)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider()

                    Text("Wikimedia and Ensu are not affiliated. Wikimedia project names identify the source material only.")
                        .font(EnsuTypography.small)
                        .foregroundStyle(EnsuColor.textMuted)
                }
                .padding(EnsuSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(EnsuColor.fillFaint)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: EnsuCornerRadius.card,
                        style: .continuous
                    )
                )
                .padding(EnsuSpacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(EnsuColor.backgroundBase)
            .navigationTitle("Attribution")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
