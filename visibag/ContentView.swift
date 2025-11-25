//
//  ContentView.swift
//  visibag
//
//  Created by Alex A on 4/10/2024.
//

import SwiftUI
import Charts
import OrderedCollections
import UniformTypeIdentifiers

struct Point : Codable, Identifiable {
    let x: Double
    let y: Double

    var id: Int { x.hashValue }

    init(from decoder: Decoder) throws {
        var values = try decoder.unkeyedContainer()
        x = try values.decode(Double.self)
        y = try values.decode(Double.self)
    }
}

struct Event: Codable, Identifiable {
    let point: Point
    let side: String
    let orderSize: Int

    var id: Int { point.id } // Not really a legit ID
}

struct Message: Codable, Identifiable {
    let key: String
    let data: OrderedDictionary<String, [Point]>
    let events: [Event]

    var id: Int { key.hashValue }
}

enum AxisType {
    case Horizontal, Vertical
}

enum BoundType {
    case Lower, Upper
}

struct ZoomingOverlay : View {
    let proxy: ChartProxy
    @Binding var bounds: Dictionary<AxisType, (Double?, Double?)>

    var body: some View {
        GeometryReader { geometry in
            Rectangle().fill(.clear).contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onEnded { value in
                            let origin = geometry[proxy.plotFrame!].origin
                            let (startX, startY) = coords(location: value.startLocation, origin: origin)
                            let (endX, endY) = coords(location: value.location, origin: origin)
                            print("Restricting horizontal axis to \(startX):\(endX)")
                            print("Restricting vertical axis to \(startY):\(endY)")

                            let (lowX, highX) = extendedRange(start: startX, end: endX)
                            let (lowY, highY) = extendedRange(start: startY, end: endY)

                            bounds[.Horizontal] = extendedRange(start: lowX, end: highX)
                            bounds[.Vertical] = extendedRange(start: lowY, end: highY)
                        }
                )
        }
    }

    func coords(location: CGPoint, origin: CGPoint) -> (Double, Double) {
        let location = CGPoint(x: location.x - origin.x, y: location.y - origin.y)
        return proxy.value(at: location) ?? (0.0, 0.0)
    }

    func extendedRange(start: Double, end: Double) -> (Double, Double){
        let (low, high) = (min(start, end), max(start, end))
        let delta = (high - low) * 0.1
        return ((low - delta), (high + delta))
    }
}

struct ContentView: View {
    @State private var message: Message?
    @State private var isImporting: Bool = false
    @State private var bounds: Dictionary<AxisType, (Double?, Double?)> = Dictionary()

    var horizontalDomain: ClosedRange<Double> {
        return domain(axis: .Horizontal)
    }

    var verticalDomain: ClosedRange<Double> {
        return domain(axis: .Vertical)
    }

    var body: some View {
        VStack {
            if let message = message {
                Chart {
                    ForEach(message.data.elements, id: \.key) { name, series in
                        ForEach (series) { point in
                            LineMark(
                                x: .value("Time", point.x),
                                y: .value("Value", point.y)
                            )
                            .foregroundStyle(by: .value("Name", name))
                        }
                        .interpolationMethod(.stepEnd)
                    }

                    ForEach(message.events) { event in
                        PointMark(
                            x: .value("Time", event.point.x),
                            y: .value("Value", event.point.y)
                        )
                        .symbol {
                            event.side == "BACK" ?
                            Image(systemName: "arrow.down").foregroundColor(.red) :
                            Image(systemName: "arrow.up").foregroundColor(.yellow)
                        }
                    }
                }
                .chartYScale(domain: verticalDomain)
                .chartXScale(domain: horizontalDomain)
                .chartYAxisLabel("Price")
                .chartXAxisLabel("Time")
                .chartOverlay { proxy in
                    ZoomingOverlay(proxy: proxy, bounds: $bounds)
                }
            } else {
                if #available(iOS 17.0, macOS 14.0, *) {
                    ContentUnavailableView("No Data", systemImage: "chart.xyaxis.line", description: Text("Import a JSON file to view the market data."))
                } else {
                    VStack(spacing: 20) {
                        Image(systemName: "chart.xyaxis.line")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No Data")
                            .font(.title2)
                            .bold()
                        Text("Import a JSON file to view the market data.")
                            .foregroundColor(.secondary)
                        Button("Import Data") {
                            isImporting = true
                        }
                    }
                }
            }
        }
        .navigationTitle("Visibag")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { isImporting = true }) {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
            }
            if message != nil {
                ToolbarItem(placement: .automatic) {
                    Button("Reset Zoom") {
                        bounds.removeAll()
                    }
                }
            }
        }
        .padding()
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                loadData(from: url)
            case .failure(let error):
                print("Error importing file: \(error.localizedDescription)")
            }
        }
    }

    func loadData(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            print("Access denied")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let data = try Data(contentsOf: url)
            let decodedMessage = try JSONDecoder().decode(Message.self, from: data)
            self.message = decodedMessage
            self.bounds.removeAll()
        } catch {
            print("Error decoding: \(error)")
        }
    }

    func domain(axis: AxisType) -> ClosedRange<Double> {
        guard let message = message else { return 0...1 }

        var (min, max) = bounds[axis] ?? (nil, nil)
        if min == nil || max == nil {
            for (_, series) in message.data {
                for point in series {
                    let val = (axis == .Horizontal) ? point.x : point.y
                    if min == nil || val < min! { min = val }
                    if max == nil || val > max! { max = val }
                }
            }
        }
        // Fallback if min/max still nil (empty data)
        let safeMin = min ?? 0.0
        let safeMax = max ?? 1.0
        return safeMin...safeMax
    }
}

#Preview {
    ContentView()
}
