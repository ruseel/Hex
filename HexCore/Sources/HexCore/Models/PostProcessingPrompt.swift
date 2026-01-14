import Foundation

public struct PostProcessingPrompt: Codable, Equatable, Identifiable, Sendable {
	public var id: UUID
	public var name: String
	public var prompt: String
	
	public init(
		id: UUID = UUID(),
		name: String,
		prompt: String
	) {
		self.id = id
		self.name = name
		self.prompt = prompt
	}
}

extension PostProcessingPrompt {
	public static let defaultPrompt = PostProcessingPrompt(
		name: "Clean Up",
		prompt: "Clean up the following transcription. Fix grammar, punctuation, and remove filler words. Keep the original meaning. Only output the cleaned text:\n\n{{text}}"
	)
}
