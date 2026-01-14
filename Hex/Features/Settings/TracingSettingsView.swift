//
//  TracingSettingsView.swift
//  Hex
//
//  Created by Amp on 1/14/26.
//

import AppKit
import ComposableArchitecture
import HexCore
import Inject
import SwiftUI

private let dockerCommand = """
docker run -d --name jaeger \\
  -p 16686:16686 \\
  -p 4317:4317 \\
  jaegertracing/all-in-one:latest
"""

struct TracingSettingsView: View {
  @ObserveInjection var inject
  @Bindable var store: StoreOf<SettingsFeature>
  @State private var showCopied = false

  var body: some View {
    Form {
      Section {
        Label {
          Toggle("Enable Tracing", isOn: $store.hexSettings.tracingEnabled)
        } icon: {
          Image(systemName: "point.3.connected.trianglepath.dotted")
        }
        
        Text("Export OpenTelemetry traces to an OTLP-compatible collector (e.g., Jaeger, Zipkin, Grafana Tempo).")
          .font(.caption)
          .foregroundStyle(.secondary)
      } header: {
        Text("OpenTelemetry")
      }
      
      Section {
        Label {
          VStack(alignment: .leading, spacing: 4) {
            Text("OTLP Endpoint")
            TextField("localhost:4317", text: $store.hexSettings.otlpEndpoint)
              .textFieldStyle(.roundedBorder)
              .font(.system(.body, design: .monospaced))
          }
        } icon: {
          Image(systemName: "network")
        }
        
        Label {
          Toggle("Use TLS", isOn: $store.hexSettings.otlpUseTLS)
          Text("Enable secure connection (required for most cloud providers)")
        } icon: {
          Image(systemName: "lock.shield")
        }
      } header: {
        Text("Collector Configuration")
      } footer: {
        Text("Changes take effect on next transcription.")
      }
      .disabled(!store.hexSettings.tracingEnabled)
      
      Section {
        VStack(alignment: .leading, spacing: 12) {
          Text("Quick Start")
            .font(.headline)
          
          Text("Run a local Jaeger collector to view traces:")
            .font(.subheadline)
          
          ZStack(alignment: .topTrailing) {
            Text(dockerCommand)
              .font(.system(.caption, design: .monospaced))
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(8)
              .padding(.trailing, 24)
              .background(Color(nsColor: .textBackgroundColor))
              .clipShape(RoundedRectangle(cornerRadius: 6))
            
            Button {
              NSPasteboard.general.clearContents()
              NSPasteboard.general.setString(dockerCommand, forType: .string)
              showCopied = true
              DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                showCopied = false
              }
            } label: {
              Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(6)
            .help("Copy to clipboard")
          }
          
          Link("Open Jaeger UI", destination: URL(string: "http://localhost:16686")!)
            .font(.subheadline)
        }
        .padding(.vertical, 4)
      } header: {
        Text("Instructions")
      }
    }
    .formStyle(.grouped)
    .enableInjection()
  }
}
