//
//  OllamaClientTests.swift
//  HexCoreTests
//
//  Created by Amp on 1/14/26.
//

import Foundation
import Testing

/// Integration tests for Ollama client - requires local Ollama instance running
/// Run with: cd HexCore && swift test --filter OllamaClientTests
struct OllamaClientTests {
  
  let endpoint = "http://localhost:11434"
  let model = "gpt-oss:20b"
  
  @Test
  func ollamaIsAvailable() async throws {
    let url = URL(string: "\(endpoint)/api/tags")!
    let (_, response) = try await URLSession.shared.data(from: url)
    guard let httpResponse = response as? HTTPURLResponse else {
      Issue.record("Invalid response type")
      return
    }
    #expect(httpResponse.statusCode == 200)
  }
  
  @Test
  func ollamaCanListModels() async throws {
    let url = URL(string: "\(endpoint)/api/tags")!
    let (data, _) = try await URLSession.shared.data(from: url)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let models = json?["models"] as? [[String: Any]]
    #expect(models != nil)
    #expect(models?.isEmpty == false)
    
    // Check if gpt-oss:20b is available
    let modelNames = models?.compactMap { $0["name"] as? String } ?? []
    print("Available models: \(modelNames)")
    #expect(modelNames.contains(model))
  }
  
  @Test
  func ollamaCanProcessSimpleText() async throws {
    let inputText = "hello world"
    let prompt = "Repeat exactly what I say: {{text}}"
    let fullPrompt = prompt.replacingOccurrences(of: "{{text}}", with: inputText)
    
    let url = URL(string: "\(endpoint)/api/generate")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 60
    
    let body: [String: Any] = [
      "model": model,
      "prompt": fullPrompt,
      "stream": false
    ]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      Issue.record("Invalid response type")
      return
    }
    #expect(httpResponse.statusCode == 200)
    
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let responseText = json?["response"] as? String
    #expect(responseText != nil)
    print("Ollama response: \(responseText ?? "nil")")
  }
  
  @Test
  func ollamaCanCleanTranscription() async throws {
    let inputText = "um hello uh this is a test um you know"
    let prompt = """
      Clean up the following transcription. Remove filler words like "um", "uh", "you know". 
      Fix punctuation. Only output the cleaned text, nothing else:
      
      {{text}}
      """
    let fullPrompt = prompt.replacingOccurrences(of: "{{text}}", with: inputText)
    
    let url = URL(string: "\(endpoint)/api/generate")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 60
    
    let body: [String: Any] = [
      "model": model,
      "prompt": fullPrompt,
      "stream": false
    ]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      Issue.record("Invalid response type")
      return
    }
    #expect(httpResponse.statusCode == 200)
    
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let responseText = json?["response"] as? String ?? ""
    let cleaned = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
    
    print("Input: \(inputText)")
    print("Cleaned: \(cleaned)")
    
    // The cleaned version should be shorter (filler words removed)
    #expect(cleaned.count <= inputText.count)
    // Should not contain "um" as a standalone word
    #expect(!cleaned.lowercased().contains("um "))
  }
}
