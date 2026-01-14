import ComposableArchitecture
import HexCore
import Inject
import SwiftUI

struct PostProcessingSectionView: View {
	@ObserveInjection var inject
	@Bindable var store: StoreOf<SettingsFeature>

	var body: some View {
		Section {
			OllamaPostProcessingView(store: store)
			OpenRouterPostProcessingView(store: store)
		} header: {
			Text("LLM Post-Processing")
		} footer: {
			Text("Use a local or cloud LLM to clean up transcriptions. OpenRouter takes precedence if both are enabled.")
				.font(.footnote)
				.foregroundColor(.secondary)
		}
		.enableInjection()
	}
}

// MARK: - Ollama Post-Processing

private struct OllamaPostProcessingView: View {
	@ObserveInjection var inject
	@Bindable var store: StoreOf<SettingsFeature>
	@State private var isExpanded = false

	var body: some View {
		DisclosureGroup(isExpanded: $isExpanded) {
			VStack(alignment: .leading, spacing: 12) {
				VStack(alignment: .leading, spacing: 4) {
					Text("Endpoint")
						.font(.subheadline)
					TextField("http://localhost:11434", text: $store.hexSettings.ollamaEndpoint)
						.textFieldStyle(.roundedBorder)
				}

				VStack(alignment: .leading, spacing: 4) {
					Text("Model")
						.font(.subheadline)
					TextField("llama3.2", text: $store.hexSettings.ollamaModel)
						.textFieldStyle(.roundedBorder)
				}

				Divider()

				PromptListView(
					prompts: store.hexSettings.ollamaPrompts,
					selectedPromptID: store.hexSettings.ollamaSelectedPromptID,
					promptBinding: { id in ollamaPromptBinding(for: id) },
					onAdd: { store.send(.addOllamaPrompt) },
					onSelect: { store.send(.selectOllamaPrompt($0)) },
					onDelete: { store.send(.deleteOllamaPrompt($0)) }
				)
			}
			.padding(.vertical, 4)
		} label: {
			Label {
				Toggle("Ollama (Local)", isOn: $store.hexSettings.ollamaPostProcessingEnabled)
			} icon: {
				Image(systemName: "desktopcomputer")
			}
		}
		.enableInjection()
	}

	private func ollamaPromptBinding(for id: UUID) -> Binding<PostProcessingPrompt>? {
		guard let index = store.hexSettings.ollamaPrompts.firstIndex(where: { $0.id == id }) else {
			return nil
		}
		return $store.hexSettings.ollamaPrompts[index]
	}
}

// MARK: - OpenRouter Post-Processing

private struct OpenRouterPostProcessingView: View {
	@ObserveInjection var inject
	@Bindable var store: StoreOf<SettingsFeature>
	@State private var isExpanded = false

	var body: some View {
		DisclosureGroup(isExpanded: $isExpanded) {
			VStack(alignment: .leading, spacing: 12) {
				VStack(alignment: .leading, spacing: 4) {
					Text("API Key")
						.font(.subheadline)
					SecureField("sk-or-...", text: $store.hexSettings.openRouterApiKey)
						.textFieldStyle(.roundedBorder)
				}

				VStack(alignment: .leading, spacing: 4) {
					Text("Model")
						.font(.subheadline)
					TextField("google/gemini-2.0-flash-001", text: $store.hexSettings.openRouterModel)
						.textFieldStyle(.roundedBorder)
				}

				Divider()

				PromptListView(
					prompts: store.hexSettings.openRouterPrompts,
					selectedPromptID: store.hexSettings.openRouterSelectedPromptID,
					promptBinding: { id in openRouterPromptBinding(for: id) },
					onAdd: { store.send(.addOpenRouterPrompt) },
					onSelect: { store.send(.selectOpenRouterPrompt($0)) },
					onDelete: { store.send(.deleteOpenRouterPrompt($0)) }
				)
			}
			.padding(.vertical, 4)
		} label: {
			Label {
				Toggle("OpenRouter (Cloud)", isOn: $store.hexSettings.openRouterPostProcessingEnabled)
			} icon: {
				Image(systemName: "cloud")
			}
		}
		.enableInjection()
	}

	private func openRouterPromptBinding(for id: UUID) -> Binding<PostProcessingPrompt>? {
		guard let index = store.hexSettings.openRouterPrompts.firstIndex(where: { $0.id == id }) else {
			return nil
		}
		return $store.hexSettings.openRouterPrompts[index]
	}
}

// MARK: - Prompt List View

private struct PromptListView: View {
	let prompts: [PostProcessingPrompt]
	let selectedPromptID: UUID?
	let promptBinding: (UUID) -> Binding<PostProcessingPrompt>?
	let onAdd: () -> Void
	let onSelect: (UUID) -> Void
	let onDelete: (UUID) -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack {
				Text("Prompts")
					.font(.subheadline.weight(.semibold))
				Spacer()
				Button {
					onAdd()
				} label: {
					Label("Add", systemImage: "plus")
				}
				.buttonStyle(.borderless)
			}

			if prompts.isEmpty {
				Text("No prompts configured")
					.foregroundStyle(.secondary)
					.font(.caption)
			} else {
				ForEach(prompts) { prompt in
					if let binding = promptBinding(prompt.id) {
						PromptRow(
							prompt: binding,
							isSelected: prompt.id == selectedPromptID,
							canDelete: prompts.count > 1,
							onSelect: { onSelect(prompt.id) },
							onDelete: { onDelete(prompt.id) }
						)
					}
				}
			}
		}
	}
}

// MARK: - Prompt Row

private struct PromptRow: View {
	@Binding var prompt: PostProcessingPrompt
	let isSelected: Bool
	let canDelete: Bool
	let onSelect: () -> Void
	let onDelete: () -> Void
	@State private var isEditing = false

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			HStack(spacing: 8) {
				Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
					.foregroundStyle(isSelected ? Color.accentColor : .secondary)
					.onTapGesture { onSelect() }

				TextField("Prompt Name", text: $prompt.name)
					.textFieldStyle(.roundedBorder)
					.frame(maxWidth: 200)

				Spacer()

				Button {
					isEditing.toggle()
				} label: {
					Image(systemName: "pencil")
				}
				.buttonStyle(.borderless)

				if canDelete {
					Button(role: .destructive) {
						onDelete()
					} label: {
						Image(systemName: "trash")
					}
					.buttonStyle(.borderless)
				}
			}

			if isEditing {
				TextEditor(text: $prompt.prompt)
					.font(.system(.body, design: .monospaced))
					.frame(height: 100)
					.scrollContentBackground(.hidden)
					.padding(8)
					.background(
						RoundedRectangle(cornerRadius: 6)
							.fill(Color(nsColor: .controlBackgroundColor))
					)
					.overlay(
						RoundedRectangle(cornerRadius: 6)
							.stroke(Color(nsColor: .separatorColor), lineWidth: 1)
					)

				Text("Use {{text}} as placeholder for the transcription")
					.settingsCaption()
			}
		}
		.padding(8)
		.background(
			RoundedRectangle(cornerRadius: 8)
				.fill(isSelected ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
		)
	}
}
