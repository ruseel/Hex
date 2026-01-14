//
//  Effect+Tracing.swift
//  Hex
//
//  Helper extension for instrumenting Effect.run bodies with OpenTelemetry spans.
//

import ComposableArchitecture
import Dependencies
import HexCore

extension Effect {
  /// Creates a traced `.run` effect that automatically manages span lifecycle.
  ///
  /// The span is:
  /// - Started before the operation begins
  /// - Ended with `.ok` on successful completion
  /// - Ended with `.error` if the operation throws
  /// - Ended with `.error("cancelled")` if the task is cancelled
  ///
  /// ## Usage
  ///
  /// ```swift
  /// return Effect.tracedRun(
  ///   spanName: "TranscriptionFeature.transcription",
  ///   parentContext: state.activeTraceContext
  /// ) { send, span in
  ///   // Access dependencies inside the closure
  ///   @Dependency(\.transcription) var transcription
  ///
  ///   // Add attributes to the span
  ///   await span.setAttribute("hex.model", model)
  ///
  ///   // Do work
  ///   let result = try await transcription.transcribe(audioURL, model, options)
  ///
  ///   // Send actions
  ///   await send(.transcriptionResult(result, audioURL))
  /// }
  /// ```
  ///
  /// - Parameters:
  ///   - spanName: Name for the span (e.g., "FeatureName.operationName")
  ///   - parentContext: Optional parent trace context for span hierarchy
  ///   - priority: Task priority for the effect
  ///   - operation: Async closure receiving `Send` and `TracedSpanHandle` for attributes/events
  /// - Returns: An instrumented Effect
  public static func tracedRun(
    spanName: String,
    parentContext: TraceContext?,
    priority: TaskPriority? = nil,
    operation: @escaping @Sendable (
      _ send: Send<Action>,
      _ span: TracedSpanHandle
    ) async throws -> Void
  ) -> Self {
    .run(priority: priority) { send in
      @Dependency(\.tracing) var tracing

      let span = await tracing.startSpan(spanName, parentContext)
      let handle = TracedSpanHandle(span: span, tracing: tracing)

      do {
        try await withTaskCancellationHandler {
          try await operation(send, handle)
          await tracing.endSpan(span, .ok)
        } onCancel: {
          Task {
            await tracing.endSpan(span, .error("cancelled"))
          }
        }
      } catch {
        await tracing.recordEvent(span, "error", ["message": error.localizedDescription])
        await tracing.endSpan(span, .error(error.localizedDescription))
        throw error
      }
    }
  }

  /// Creates a traced `.run` effect without access to the span handle.
  ///
  /// Use this simpler variant when you don't need to add attributes or events to the span.
  ///
  /// - Parameters:
  ///   - spanName: Name for the span
  ///   - parentContext: Optional parent trace context
  ///   - priority: Task priority for the effect
  ///   - operation: Async closure receiving only `Send`
  /// - Returns: An instrumented Effect
  public static func tracedRun(
    spanName: String,
    parentContext: TraceContext?,
    priority: TaskPriority? = nil,
    operation: @escaping @Sendable (_ send: Send<Action>) async throws -> Void
  ) -> Self {
    tracedRun(spanName: spanName, parentContext: parentContext, priority: priority) { send, _ in
      try await operation(send)
    }
  }
}

/// Handle for adding attributes and events to an active span within a traced effect.
///
/// This provides a convenient interface without requiring direct access to `TracingClient`.
public struct TracedSpanHandle: Sendable {
  private let span: ActiveSpan
  private let tracing: TracingClient

  init(span: ActiveSpan, tracing: TracingClient) {
    self.span = span
    self.tracing = tracing
  }

  /// The trace context of this span, for creating child spans.
  public var context: TraceContext {
    span.context
  }

  /// Add a string attribute to the span.
  public func setAttribute(_ key: String, _ value: String) async {
    await tracing.setAttribute(span, key, value)
  }

  /// Record an event on the span.
  public func recordEvent(_ name: String, attributes: [String: String] = [:]) async {
    await tracing.recordEvent(span, name, attributes)
  }

  /// Start a child span under this span.
  ///
  /// Note: You are responsible for ending child spans.
  public func startChildSpan(_ name: String) async -> ActiveSpan {
    await tracing.startSpan(name, span.context)
  }

  /// End a child span.
  public func endChildSpan(_ childSpan: ActiveSpan, status: SpanStatus) async {
    await tracing.endSpan(childSpan, status)
  }
}

// MARK: - Pipeline Span Helpers

/// Helper for managing long-lived pipeline spans that stay open across multiple actions.
///
/// Use this for workflows like transcription where the span starts in one action
/// and ends in a different action (success, error, or cancel).
public struct PipelineSpanManager: Sendable {
  
  /// Start a new pipeline span and return its context.
  ///
  /// The span will NOT be auto-ended - you must call `endPipelineSpan` when the pipeline completes.
  ///
  /// - Parameters:
  ///   - name: The span name (e.g., "transcription-pipeline")
  ///   - attributes: Initial attributes to set on the span
  /// - Returns: The trace context to store in state
  public static func startPipelineSpan(
    name: String,
    attributes: [String: String] = [:]
  ) async -> TraceContext {
    @Dependency(\.tracing) var tracing
    let span = await tracing.startSpan(name, nil)
    for (key, value) in attributes {
      await tracing.setAttribute(span, key, value)
    }
    return span.context
  }
  
  /// End a pipeline span with the given status.
  ///
  /// Optionally adds a terminal child span (e.g., "completed", "cancelled", "error").
  ///
  /// - Parameters:
  ///   - context: The trace context from startPipelineSpan
  ///   - status: The final status of the pipeline
  ///   - terminalSpanName: Optional name for a terminal child span (e.g., "completed")
  public static func endPipelineSpan(
    context: TraceContext,
    status: SpanStatus,
    terminalSpanName: String? = nil
  ) async {
    @Dependency(\.tracing) var tracing
    
    if let terminalName = terminalSpanName {
      let terminalSpan = await tracing.startSpan(terminalName, context)
      await tracing.endSpan(terminalSpan, status)
    }
    
    await tracing.endSpanByContext(context, status)
  }
  
  /// Create a child span under an existing pipeline context.
  ///
  /// Use `Effect.tracedRun` with the returned context as parent for auto-managed child spans,
  /// or manually manage with `TracingClient` for complex cases.
  public static func createChildSpan(
    name: String,
    parentContext: TraceContext,
    attributes: [String: String] = [:]
  ) async -> ActiveSpan {
    @Dependency(\.tracing) var tracing
    let span = await tracing.startSpan(name, parentContext)
    for (key, value) in attributes {
      await tracing.setAttribute(span, key, value)
    }
    return span
  }
}
