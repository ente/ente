import SwiftUI

struct KnowledgeSettingsView: View {
    @ObservedObject var store: KnowledgeStore
    @State private var attributionPack: KnowledgePackState?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: EnsuSpacing.md) {
                Text(
                    "Choose packs for future messages in all chats. Existing answers stay unchanged."
                )
                .font(EnsuTypography.small).foregroundStyle(EnsuColor.textMuted)
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
        EnsuCard {
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
                if pack.activeIdentity != nil {
                    Toggle(
                        "Use \(pack.config.label) for future messages",
                        isOn: Binding(
                            get: { !store.disabledIDs.contains(pack.id) },
                            set: {
                                store.setEnabled(pack.id, enabled: $0)
                            })
                    )
                    .labelsHidden()
                    .tint(EnsuColor.accent)
                    .disabled(pack.isMutating)
                } else if store.downloadsAllowed && pack.status == .download && !pack.isMutating {
                    CompactButton(text: "Download") {
                        store.downloadOrUpdate(stableId: pack.id)
                    }
                }
            }

            if pack.isMutating {
                HStack(spacing: EnsuSpacing.sm) {
                    ProgressView(value: Double(pack.progressPercent ?? 0), total: 100)
                        .tint(EnsuColor.action)
                    Button {
                        store.cancel(stableId: pack.id)
                    } label: {
                        Image("Cancel01Icon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 12, height: 12)
                            .foregroundStyle(EnsuColor.textMuted)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Cancel download")
                }
            } else if store.downloadsAllowed && pack.status == .updateAvailable {
                CompactButton(text: "Update") {
                    store.downloadOrUpdate(stableId: pack.id)
                }
            }

            if pack.isMutating, let progress = pack.progressLabel {
                Text(progress)
                    .font(EnsuTypography.small)
                    .foregroundStyle(EnsuColor.textMuted)
            }

            if let error = pack.errorMessage {
                Text(error)
                    .font(EnsuTypography.small)
                    .foregroundStyle(EnsuColor.error)
            }
        }
    }
}

private struct PackAttributionSheet: View {
    let config: KnowledgeDatasetConfig

    var body: some View {
        let attribution = config.attribution
        AttributionSheet(title: "Attribution") {
            EnsuCard(padding: EnsuSpacing.md) {
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
                    if let sourceUrl = URL(string: attribution.publicPackUrl) {
                        Link(destination: sourceUrl) {
                            Label("Source", systemImage: "arrow.up.right.square")
                                .frame(minHeight: 44)
                        }
                    }
                    if let licenseUrl = URL(string: attribution.licenseUrl) {
                        Link(destination: licenseUrl) {
                            Label("License", systemImage: "doc.text")
                                .frame(minHeight: 44)
                        }
                    }
                }
                .font(EnsuTypography.mini)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                Text(
                    "Wikimedia and Ensu are not affiliated. Wikimedia project names identify the source material only."
                )
                .font(EnsuTypography.small)
                .foregroundStyle(EnsuColor.textMuted)
            }
        }
    }
}
