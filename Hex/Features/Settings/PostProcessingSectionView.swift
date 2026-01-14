import ComposableArchitecture
import HexCore
import Inject
import SwiftUI

struct PostProcessingSectionView: View {
	@ObserveInjection var inject
	@Bindable var store: StoreOf<SettingsFeature>

	var body: some View {
		Section {
			LLMProviderView(
				store: store,
				provider: .ollama
			)
			LLMProviderView(
				store: store,
				provider: .openRouter
			)
		} header: {
			Text("LLM Post-Processing")
		} footer: {
			Text("Use a local or cloud LLM to clean up transcriptions. Only one provider can be enabled at a time.")
				.font(.footnote)
				.foregroundColor(.secondary)
		}
		.enableInjection()
	}
}

// MARK: - LLM Provider Configuration

private enum LLMProvider {
	case ollama
	case openRouter

	var title: String {
		switch self {
		case .ollama: "Ollama (Local)"
		case .openRouter: "OpenRouter (Cloud)"
		}
	}

	var icon: String {
		switch self {
		case .ollama: "desktopcomputer"
		case .openRouter: "cloud"
		}
	}

	var connectionFields: [(label: String, placeholder: String, isSecure: Bool)] {
		switch self {
		case .ollama:
			[
				(label: "Endpoint", placeholder: "http://localhost:11434", isSecure: false),
				(label: "Model", placeholder: "llama3.2", isSecure: false)
			]
		case .openRouter:
			[
				(label: "API Key", placeholder: "sk-or-...", isSecure: true),
				(label: "Model", placeholder: "google/gemini-2.0-flash-001", isSecure: false)
			]
		}
	}
}

private struct LLMProviderView: View {
	@ObserveInjection var inject
	@Bindable var store: StoreOf<SettingsFeature>
	let provider: LLMProvider
	@State private var isExpanded = false

	private var isEnabled: Bool {
		switch provider {
		case .ollama: store.hexSettings.ollamaPostProcessingEnabled
		case .openRouter: store.hexSettings.openRouterPostProcessingEnabled
		}
	}

	private var enabledBinding: Binding<Bool> {
		Binding(
			get: { isEnabled },
			set: { newValue in
				if newValue {
					switch provider {
					case .ollama: store.send(.enableOllama)
					case .openRouter: store.send(.enableOpenRouter)
					}
				} else {
					store.send(.disablePostProcessing(
						provider == .ollama ? .ollama : .openRouter
					))
				}
			}
		)
	}

	private var prompts: [PostProcessingPrompt] {
		switch provider {
		case .ollama: store.hexSettings.ollamaPrompts
		case .openRouter: store.hexSettings.openRouterPrompts
		}
	}

	private var selectedPromptID: UUID? {
		switch provider {
		case .ollama: store.hexSettings.ollamaSelectedPromptID
		case .openRouter: store.hexSettings.openRouterSelectedPromptID
		}
	}

	var body: some View {
		DisclosureGroup(isExpanded: $isExpanded) {
			VStack(alignment: .leading, spacing: 12) {
				connectionFieldsView
				Divider()
				PromptListView(
					prompts: prompts,
					selectedPromptID: selectedPromptID,
					promptBinding: promptBinding,
					onAdd: { sendPromptAction(.add) },
					onSelect: { sendPromptAction(.select($0)) },
					onDelete: { sendPromptAction(.delete($0)) }
				)
			}
			.padding(.vertical, 4)
		} label: {
			Label {
				Toggle(provider.title, isOn: enabledBinding)
			} icon: {
				Image(systemName: provider.icon)
			}
		}
		.enableInjection()
	}

	@ViewBuilder
	private var connectionFieldsView: some View {
		switch provider {
		case .ollama:
			ConfigTextField(label: "Endpoint", placeholder: "http://localhost:11434", text: $store.hexSettings.ollamaEndpoint)
			ConfigTextField(label: "Model", placeholder: "llama3.2", text: $store.hexSettings.ollamaModel)
		case .openRouter:
			ConfigSecureField(label: "API Key", placeholder: "sk-or-...", text: $store.hexSettings.openRouterApiKey)
			ConfigTextField(label: "Model", placeholder: "google/gemini-2.0-flash-001", text: $store.hexSettings.openRouterModel)
		}
	}

	private func promptBinding(for id: UUID) -> Binding<PostProcessingPrompt>? {
		switch provider {
		case .ollama:
			guard let index = store.hexSettings.ollamaPrompts.firstIndex(where: { $0.id == id }) else { return nil }
			return $store.hexSettings.ollamaPrompts[index]
		case .openRouter:
			guard let index = store.hexSettings.openRouterPrompts.firstIndex(where: { $0.id == id }) else { return nil }
			return $store.hexSettings.openRouterPrompts[index]
		}
	}

	private enum PromptAction {
		case add
		case select(UUID)
		case delete(UUID)
	}

	private func sendPromptAction(_ action: PromptAction) {
		switch (provider, action) {
		case (.ollama, .add): store.send(.addOllamaPrompt)
		case (.ollama, .select(let id)): store.send(.selectOllamaPrompt(id))
		case (.ollama, .delete(let id)): store.send(.deleteOllamaPrompt(id))
		case (.openRouter, .add): store.send(.addOpenRouterPrompt)
		case (.openRouter, .select(let id)): store.send(.selectOpenRouterPrompt(id))
		case (.openRouter, .delete(let id)): store.send(.deleteOpenRouterPrompt(id))
		}
	}
}

// MARK: - Config Field Components

private struct ConfigTextField: View {
	let label: String
	let placeholder: String
	@Binding var text: String

	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			Text(label)
				.font(.subheadline)
			TextField(placeholder, text: $text)
				.textFieldStyle(.roundedBorder)
		}
	}
}

private struct ConfigSecureField: View {
	let label: String
	let placeholder: String
	@Binding var text: String

	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			Text(label)
				.font(.subheadline)
			SecureField(placeholder, text: $text)
				.textFieldStyle(.roundedBorder)
		}
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
