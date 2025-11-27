import SwiftUI
import Charts
import OrderedCollections
import UniformTypeIdentifiers

struct Point: Codable, Identifiable {
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
    var chartIndex: Int?
    
    var id: Int { point.id }
}

struct ChartGroup: Codable, Identifiable {
    let name: String
    let data: [String: [Point]]
    
    var id: String { name }
}

struct Message: Decodable, Identifiable {
    let key: String
    let charts: [ChartGroup]
    let events: [Event]
    
    var id: Int { key.hashValue }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        events = try container.decodeIfPresent([Event].self, forKey: .events) ?? []
        
        if container.contains(.charts) {
            self.charts = try container.decode([ChartGroup].self, forKey: .charts)
        } else if container.contains(.data) {
            let data = try container.decode(Dictionary<String, [Point]>.self, forKey: .data)
            self.charts = [ChartGroup(name: "Default", data: data)]
        } else {
            self.charts = []
        }
    }
    
    private enum CodingKeys: String, CodingKey {
        case key, charts, data, events
    }
}

struct ZoomingOverlay: View {
    let proxy: ChartProxy
    let onZoom: (Double, Double, Double, Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            Rectangle().fill(.clear).contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onEnded { value in
                            let origin = geometry[proxy.plotFrame!].origin
                            let (startX, startY) = coords(location: value.startLocation, origin: origin)
                            let (endX, endY) = coords(location: value.location, origin: origin)
                            
                            let (lowX, highX) = extendedRange(start: startX, end: endX)
                            let (lowY, highY) = extendedRange(start: startY, end: endY)
                            
                            onZoom(lowX, highX, lowY, highY)
                        }
                )
        }
    }

    func coords(location: CGPoint, origin: CGPoint) -> (Double, Double) {
        let location = CGPoint(x: location.x - origin.x, y: location.y - origin.y)
        return proxy.value(at: location) ?? (0.0, 0.0)
    }

    func extendedRange(start: Double, end: Double) -> (Double, Double) {
        let (low, high) = (min(start, end), max(start, end))
        let delta = (high - low) * 0.1
        return (low - delta, high + delta)
    }
}

struct SingleChartView: View {
    let chartGroup: ChartGroup
    let events: [Event]
    let horizontalDomain: ClosedRange<Double>
    let verticalBounds: (Double?, Double?)
    let onZoom: (Double, Double, Double, Double) -> Void
    
    var verticalDomain: ClosedRange<Double> {
        var (min, max) = verticalBounds
        if min == nil || max == nil {
            for (_, series) in chartGroup.data {
                for point in series {
                    if min == nil || point.y < min! { min = point.y }
                    if max == nil || point.y > max! { max = point.y }
                }
            }
        }
        let safeMin = min ?? 0.0
        let safeMax = max ?? 1.0
        return safeMin...safeMax
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(chartGroup.name)
                .font(.headline)
                .foregroundColor(.secondary)
            
            Chart {
                ForEach(chartGroup.data.keys.sorted(), id: \.self) { name in let series = chartGroup.data[name]!
                    ForEach(series) { point in
                        LineMark(
                            x: .value("Time", point.x),
                            y: .value("Value", point.y)
                        )
                        .foregroundStyle(by: .value("Name", name))
                    }
                    .interpolationMethod(.stepEnd)
                }
                
                ForEach(events) { event in
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
            .chartYAxisLabel(chartGroup.name)
            .chartOverlay { proxy in
                ZoomingOverlay(proxy: proxy, onZoom: onZoom)
            }
        }
    }
}

struct ContentView: View {
    @State private var message: Message?
    @State private var isImporting: Bool = false
    @State private var horizontalBounds: (Double?, Double?) = (nil, nil)
    @State private var verticalBoundsPerChart: [String: (Double?, Double?)] = [:]

    var horizontalDomain: ClosedRange<Double> {
        guard let message = message else { return 0...1 }
        
        var (min, max) = horizontalBounds
        if min == nil || max == nil {
            for chart in message.charts {
                for (_, series) in chart.data {
                    for point in series {
                        if min == nil || point.x < min! { min = point.x }
                        if max == nil || point.x > max! { max = point.x }
                    }
                }
            }
        }
        return (min ?? 0.0)...(max ?? 1.0)
    }

    var body: some View {
        VStack {
            if let message = message {
                ScrollView {
                    VStack(spacing: 20) {
                        ForEach(Array(message.charts.enumerated()), id: \.element.id) { index, chartGroup in
                            let chartEvents = message.events.filter { $0.chartIndex == index || ($0.chartIndex == nil && index == 0) }
                            
                            SingleChartView(
                                chartGroup: chartGroup,
                                events: chartEvents,
                                horizontalDomain: horizontalDomain,
                                verticalBounds: verticalBoundsPerChart[chartGroup.name] ?? (nil, nil),
                                onZoom: { lowX, highX, lowY, highY in
                                    horizontalBounds = (lowX, highX)
                                    verticalBoundsPerChart[chartGroup.name] = (lowY, highY)
                                }
                            )
                            .frame(minHeight: 200)
                        }
                    }
                    .padding()
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
                        horizontalBounds = (nil, nil)
                        verticalBoundsPerChart.removeAll()
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
            print("Loaded \(decodedMessage.charts.count) charts:")
            for chart in decodedMessage.charts {
                print("  - '\(chart.name)' with \(chart.data.count) series")
            }
            self.message = decodedMessage
            self.horizontalBounds = (nil, nil)
            self.verticalBoundsPerChart.removeAll()
        } catch {
            print("Error decoding: \(error)")
        }
    }
}

#Preview {
    ContentView()
}
