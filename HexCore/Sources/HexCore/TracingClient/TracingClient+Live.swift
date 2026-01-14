//
//  TracingClient+Live.swift
//  HexCore
//
//  Created by Amp on 1/14/26.
//

import Dependencies
import Foundation
import GRPC
import NIO
import OpenTelemetryApi
import OpenTelemetryProtocolExporterGrpc
import OpenTelemetrySdk
import StdoutExporter

/// Configuration for the tracing client
public struct TracingConfiguration: Equatable, Sendable {
  public let enabled: Bool
  public let endpoint: String
  public let useTLS: Bool
  
  public init(enabled: Bool, endpoint: String, useTLS: Bool) {
    self.enabled = enabled
    self.endpoint = endpoint
    self.useTLS = useTLS
  }
  
  public static let disabled = TracingConfiguration(enabled: false, endpoint: "localhost:4317", useTLS: false)
}

extension TracingClient: DependencyKey {
  public static var liveValue: Self {
    let actor = TracingActor.shared
    
    return Self(
      startSpan: { name, parentContext in
        await actor.startSpan(name: name, parentContext: parentContext)
      },
      endSpan: { span, status in
        await actor.endSpan(span: span, status: status)
      },
      setAttribute: { span, key, value in
        await actor.setAttribute(span: span, key: key, value: value)
      },
      recordEvent: { span, name, attributes in
        await actor.recordEvent(span: span, name: name, attributes: attributes)
      },
      endSpanByContext: { context, status in
        await actor.endSpanByContext(context: context, status: status)
      }
    )
  }
}

/// Actor that manages OpenTelemetry tracer and span lifecycle.
/// Reads configuration from HexSettings on each span creation.
actor TracingActor {
  static let shared = TracingActor()
  
  private var tracer: Tracer?
  private var activeSpans: [String: Span] = [:]
  private var currentConfig: TracingConfiguration?
  private var eventLoopGroup: EventLoopGroup?
  private var hasRegisteredProvider = false
  
  private init() {}
  
  private func ensureConfigured() -> Tracer? {
    let config = loadConfiguration()
    
    guard config.enabled else {
      return nil
    }
    
    if currentConfig != config || tracer == nil {
      if let newTracer = configureTracer(with: config) {
        tracer = newTracer
        currentConfig = config
      } else {
        return nil
      }
    }
    
    return tracer
  }
  
  private func loadConfiguration() -> TracingConfiguration {
    let settings = HexSettings()
    
    do {
      let url = try URL.hexApplicationSupport.appending(component: "hex_settings.json")
      if FileManager.default.fileExists(atPath: url.path) {
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(HexSettings.self, from: data)
        return TracingConfiguration(
          enabled: decoded.tracingEnabled,
          endpoint: decoded.otlpEndpoint,
          useTLS: decoded.otlpUseTLS
        )
      }
    } catch {
      // Fall through to defaults
    }
    
    return TracingConfiguration(
      enabled: settings.tracingEnabled,
      endpoint: settings.otlpEndpoint,
      useTLS: settings.otlpUseTLS
    )
  }
  
  private func configureTracer(with config: TracingConfiguration) -> Tracer? {
    let serviceName = "hex-transcription"
    
    let (host, port) = parseEndpoint(config.endpoint)
    
    if eventLoopGroup == nil {
      eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }
    
    let channel: GRPCChannel
    do {
      if config.useTLS {
        channel = try GRPCChannelPool.with(
          target: .host(host, port: port),
          transportSecurity: .tls(.makeClientDefault(compatibleWith: eventLoopGroup!)),
          eventLoopGroup: eventLoopGroup!
        )
      } else {
        channel = try GRPCChannelPool.with(
          target: .host(host, port: port),
          transportSecurity: .plaintext,
          eventLoopGroup: eventLoopGroup!
        )
      }
    } catch {
      HexLog.tracing.error("Failed to create GRPC channel: \(error.localizedDescription)")
      return nil
    }
    
    let otlpExporter = OtlpTraceExporter(channel: channel)
    let stdoutExporter = StdoutSpanExporter()
    
    let spanProcessor = MultiSpanProcessor(spanProcessors: [
      SimpleSpanProcessor(spanExporter: stdoutExporter),
      BatchSpanProcessor(spanExporter: otlpExporter),
    ])
    
    let tracerProvider = TracerProviderBuilder()
      .add(spanProcessor: spanProcessor)
      .with(resource: Resource(attributes: [
        ResourceAttributes.serviceName.rawValue: .string(serviceName),
        ResourceAttributes.serviceVersion.rawValue: .string(
          Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        ),
      ]))
      .build()
    
    if !hasRegisteredProvider {
      OpenTelemetry.registerTracerProvider(tracerProvider: tracerProvider)
      hasRegisteredProvider = true
    }
    
    return tracerProvider.get(
      instrumentationName: serviceName,
      instrumentationVersion: "1.0.0"
    )
  }
  
  private func parseEndpoint(_ endpoint: String) -> (host: String, port: Int) {
    let components = endpoint.split(separator: ":")
    let host = components.first.map(String.init) ?? "localhost"
    let port = components.dropFirst().first.flatMap { Int($0) } ?? 4317
    return (host, port)
  }
  
  func startSpan(name: String, parentContext: TraceContext?) -> ActiveSpan {
    guard let tracer = ensureConfigured() else {
      return ActiveSpan(
        name: name,
        context: TraceContext(traceID: "", spanID: ""),
        endAction: {}
      )
    }
    
    let spanBuilder = tracer.spanBuilder(spanName: name)
    
    if let parentContext = parentContext,
       let parentSpan = activeSpans[parentContext.spanID] {
      spanBuilder.setParent(parentSpan)
    }
    
    let span = spanBuilder.startSpan()
    let spanContext = span.context
    
    let traceID = spanContext.traceId.hexString
    let spanID = spanContext.spanId.hexString
    
    activeSpans[spanID] = span
    
    return ActiveSpan(
      name: name,
      context: TraceContext(traceID: traceID, spanID: spanID),
      endAction: {
        Task {
          await TracingActor.shared.doEndSpan(spanID: spanID, status: .ok)
        }
      }
    )
  }
  
  func endSpan(span: ActiveSpan, status: SpanStatus) {
    doEndSpan(spanID: span.context.spanID, status: status)
  }
  
  func doEndSpan(spanID: String, status: SpanStatus) {
    guard let span = activeSpans.removeValue(forKey: spanID) else { return }
    
    switch status {
    case .ok:
      span.status = .ok
    case .error(let message):
      span.status = .error(description: message)
    }
    
    span.end()
  }
  
  func setAttribute(span: ActiveSpan, key: String, value: String) {
    guard let otelSpan = activeSpans[span.context.spanID] else { return }
    otelSpan.setAttribute(key: key, value: value)
  }
  
  func recordEvent(span: ActiveSpan, name: String, attributes: [String: String]) {
    guard let otelSpan = activeSpans[span.context.spanID] else { return }
    
    var otelAttributes: [String: AttributeValue] = [:]
    for (key, value) in attributes {
      otelAttributes[key] = .string(value)
    }
    
    otelSpan.addEvent(name: name, attributes: otelAttributes)
  }
  
  func endSpanByContext(context: TraceContext, status: SpanStatus) {
    doEndSpan(spanID: context.spanID, status: status)
  }
}

private extension URL {
  static var hexApplicationSupport: URL {
    get throws {
      let fm = FileManager.default
      let appSupport = try fm.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      )
      return appSupport.appending(component: "com.kitlangton.Hex")
    }
  }
}
