import SwiftUI
import SkillDeckCore

struct ParameterFillSheet: View {
    let pending: InjectCoordinator.PendingFill
    let onInject: ([String: String]) -> Void
    let onCancel: () -> Void

    @State private var values: [String: String] = [:]

    private var allRequiredFilled: Bool {
        pending.placeholders
            .filter(\.required)
            .allSatisfy { !(values[$0.name, default: ""].isEmpty) }
    }

    private var preview: String {
        ArgumentPlaceholders.fill(pending.template, values: values)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "text.cursor")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fill Parameters")
                        .font(.system(.headline, design: .rounded).weight(.bold))
                    Text(pending.node.name)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()

            // Fields
            VStack(alignment: .leading, spacing: 12) {
                ForEach(pending.placeholders, id: \.token) { ph in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Text(ph.name)
                                .font(.system(.callout, design: .rounded).weight(.semibold))
                            if ph.required {
                                Text("required")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor, in: Capsule())
                            } else {
                                Text("optional")
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.15), in: Capsule())
                            }
                        }
                        TextField(ph.required ? "Enter \(ph.name)…" : "\(ph.name) (leave blank to omit)",
                                  text: Binding(
                                    get: { values[ph.name, default: ""] },
                                    set: { values[ph.name] = $0 }
                                  ))
                        .textFieldStyle(.plain)
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(
                                    ph.required && values[ph.name, default: ""].isEmpty
                                        ? Color.accentColor.opacity(0.4)
                                        : Color.primary.opacity(0.10),
                                    lineWidth: 1
                                )
                        )
                    }
                }
            }

            // Preview
            VStack(alignment: .leading, spacing: 6) {
                Text("PREVIEW")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Text(preview)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }

            // Buttons
            HStack(spacing: 10) {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    onInject(values)
                } label: {
                    Label("Inject", systemImage: "arrow.down.doc.fill")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!allRequiredFilled)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 420, maxWidth: 520)
    }
}
