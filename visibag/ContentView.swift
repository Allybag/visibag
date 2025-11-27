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

struct ChartGroup: Decodable, Identifiable {
    let name: String
    let data: [String: [Point]]
    
    var id: String { name }
}

struct Message: Decodable, Identifiable {
    let key: String
    let charts: [ChartGroup]
    let events: [Event]

    var id: Int { key.hashValue }
}

func partialKey(from seriesName: String) -> String {
    seriesName.components(separatedBy: " ").first ?? seriesName
}

struct PartialKeyColors {
    private var colorMap: [String: Color] = [:]
    
    private let palette: [Color] = [
        .blue, .red, .green, .orange, .purple,
        .cyan, .pink, .yellow, .mint, .indigo,
        .brown, .teal
    ]
    
    mutating func buildColors(for keys: [String]) {
        colorMap.removeAll()
        for (index, key) in keys.enumerated() {
            colorMap[key] = palette[index % palette.count]
        }
    }
    
    func color(for key: String) -> Color {
        colorMap[key] ?? .gray
    }
    
    var allKeys: [String] {
        Array(colorMap.keys).sorted()
    }
}

struct ZoomingOverlay: View {
    let proxy: ChartProxy
    let onZoom: (Double, Double, Double, Double) -> Void
    let onTap: (Double) -> Void

    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 5)
                            .onChanged { value in
                                dragStart = value.startLocation
                                dragCurrent = value.location
                            }
                            .onEnded { value in
                                let origin = geometry[proxy.plotFrame!].origin
                                let (startX, startY) = coords(location: value.startLocation, origin: origin)
                                let (endX, endY) = coords(location: value.location, origin: origin)

                                let (lowX, highX) = extendedRange(start: startX, end: endX)
                                let (lowY, highY) = extendedRange(start: startY, end: endY)

                                onZoom(lowX, highX, lowY, highY)

                                dragStart = nil
                                dragCurrent = nil
                            }
                    )
                    .onTapGesture { location in
                        let origin = geometry[proxy.plotFrame!].origin
                        let (x, _) = coords(location: location, origin: origin)
                        onTap(x)
                    }

                if let start = dragStart, let current = dragCurrent {
                    let rect = CGRect(
                        x: min(start.x, current.x),
                        y: min(start.y, current.y),
                        width: abs(current.x - start.x),
                        height: abs(current.y - start.y)
                    )

                    Rectangle()
                        .fill(Color.blue.opacity(0.15))
                        .overlay(
                            Rectangle()
                                .stroke(Color.blue.opacity(0.6), lineWidth: 1)
                        )
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
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

struct LegendView: View {
    let partialKeys: [String]
    @Binding var enabledKeys: Set<String>
    let colorForKey: (String) -> Color
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(partialKeys, id: \.self) { key in
                    Button {
                        if enabledKeys.contains(key) {
                            enabledKeys.remove(key)
                        } else {
                            enabledKeys.insert(key)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: enabledKeys.contains(key) ? "checkmark.square.fill" : "square")
                                .foregroundColor(colorForKey(key))
                            Text(key)
                                .foregroundColor(.primary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
    }
}

func seriesSuffix(from seriesName: String) -> String {
    let components = seriesName.components(separatedBy: " ")
    return components.dropFirst().joined(separator: " ")
}

func suffixOrder(for chartGroup: ChartGroup, suffix: String) -> Int {
    let allSuffixes = Array(Set(chartGroup.data.keys.map { seriesSuffix(from: $0) })).sorted()
    return allSuffixes.firstIndex(of: suffix) ?? 0
}

struct LineStyles {
    private static let styles: [StrokeStyle] = [
        StrokeStyle(lineWidth: 2),
        StrokeStyle(lineWidth: 2, dash: [5, 3]),
        StrokeStyle(lineWidth: 2, dash: [2, 2]),
        StrokeStyle(lineWidth: 2, dash: [8, 4, 2, 4]),
    ]

    static func style(for index: Int) -> StrokeStyle {
        styles[index % styles.count]
    }
}

struct SingleChartView: View {
    let chartGroup: ChartGroup
    let events: [Event]
    let horizontalDomain: ClosedRange<Double>
    let verticalBounds: (Double?, Double?)
    let enabledKeys: Set<String>
    let colorForKey: (String) -> Color
    let allPartialKeys: [String]
    let cursorX: Double?
    let onZoom: (Double, Double, Double, Double) -> Void
    let onTap: (Double) -> Void

    var filteredData: [(name: String, series: [Point])] {
        chartGroup.data.keys.sorted().compactMap { name in
            let key = partialKey(from: name)
            guard enabledKeys.contains(key) else { return nil }
            return (name: name, series: chartGroup.data[name]!)
        }
    }

    func valueAtCursor(series: [Point], x: Double) -> Double? {
        // Find the last point with x <= cursor (step interpolation)
        var result: Double?
        for point in series {
            if point.x <= x {
                result = point.y
            } else {
                break
            }
        }
        return result
    }

    var cursorValues: [(name: String, value: Double)] {
        guard let x = cursorX else { return [] }
        return filteredData.compactMap { name, series in
            guard let value = valueAtCursor(series: series, x: x) else { return nil }
            return (name: name, value: value)
        }
    }
    
    var verticalDomain: ClosedRange<Double> {
        var (min, max) = verticalBounds
        if min == nil || max == nil {
            for (_, series) in filteredData {
                for point in series {
                    guard point.x >= horizontalDomain.lowerBound && point.x <= horizontalDomain.upperBound else {
                        continue
                    }
                    if min == nil || point.y < min! { min = point.y }
                    if max == nil || point.y > max! { max = point.y }
                }
            }
        }
        let safeMin = min ?? 0.0
        let safeMax = max ?? 1.0
        let padding = (safeMax - safeMin) * 0.05
        return (safeMin - padding)...(safeMax + padding)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(chartGroup.name)
                .font(.headline)
                .foregroundColor(.secondary)

            if !cursorValues.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(cursorValues, id: \.name) { name, value in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(colorForKey(partialKey(from: name)))
                                    .frame(width: 8, height: 8)
                                Text("\(name): \(value, specifier: "%.2f")")
                                    .font(.caption)
                            }
                        }
                    }
                }
            }

            Chart {
                ForEach(filteredData, id: \.name) { name, series in
                    let key = partialKey(from: name)
                    let suffix = seriesSuffix(from: name)
                    let suffixIndex = suffixOrder(for: chartGroup, suffix: suffix)

                    ForEach(series) { point in
                        LineMark(
                            x: .value("Time", point.x),
                            y: .value("Value", point.y),
                            series: .value("Series", name)
                        )
                        .foregroundStyle(by: .value("Key", key))
                        .lineStyle(LineStyles.style(for: suffixIndex))
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

                if let x = cursorX {
                    RuleMark(x: .value("Cursor", x))
                        .foregroundStyle(.gray.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                }
            }
            .chartYScale(domain: verticalDomain)
            .chartXScale(domain: horizontalDomain)
            .chartYAxisLabel(chartGroup.name)
            .chartLegend(.hidden)
            .chartForegroundStyleScale(domain: allPartialKeys, range: allPartialKeys.map { colorForKey($0) })
            .chartOverlay { proxy in
                ZoomingOverlay(proxy: proxy, onZoom: onZoom, onTap: onTap)
            }
        }
    }
}

struct ContentView: View {
    @State private var message: Message?
    @State private var isImporting: Bool = false
    @State private var horizontalBounds: (Double?, Double?) = (nil, nil)
    @State private var verticalBoundsPerChart: [String: (Double?, Double?)] = [:]
    @State private var partialKeyColors = PartialKeyColors()
    @State private var enabledPartialKeys: Set<String> = []
    @State private var cursorX: Double?

    var horizontalDomain: ClosedRange<Double> {
        guard let message = message else { return 0...1 }
        
        var (min, max) = horizontalBounds
        if min == nil || max == nil {
            for chart in message.charts {
                for (name, series) in chart.data {
                    guard enabledPartialKeys.contains(partialKey(from: name)) else { continue }
                    for point in series {
                        if min == nil || point.x < min! { min = point.x }
                        if max == nil || point.x > max! { max = point.x }
                    }
                }
            }
        }
        return (min ?? 0.0)...(max ?? 1.0)
    }
    
    var allPartialKeys: [String] {
        partialKeyColors.allKeys
    }

    var body: some View {
        VStack(spacing: 0) {
            if let message = message {
                LegendView(
                    partialKeys: allPartialKeys,
                    enabledKeys: $enabledPartialKeys,
                    colorForKey: { partialKeyColors.color(for: $0) }
                )
                
                Divider()
                
                ScrollView {
                    VStack(spacing: 20) {
                        ForEach(Array(message.charts.enumerated()), id: \.element.id) { index, chartGroup in
                            let chartEvents = message.events.filter { $0.chartIndex == index || ($0.chartIndex == nil && index == 0) }
                            
                            SingleChartView(
                                chartGroup: chartGroup,
                                events: chartEvents,
                                horizontalDomain: horizontalDomain,
                                verticalBounds: verticalBoundsPerChart[chartGroup.name] ?? (nil, nil),
                                enabledKeys: enabledPartialKeys,
                                colorForKey: { partialKeyColors.color(for: $0) },
                                allPartialKeys: allPartialKeys,
                                cursorX: cursorX,
                                onZoom: { lowX, highX, lowY, highY in
                                    horizontalBounds = (lowX, highX)
                                    verticalBoundsPerChart[chartGroup.name] = (lowY, highY)
                                },
                                onTap: { x in
                                    cursorX = x
                                }
                            )
                            .frame(minHeight: 200)
                        }
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView("No Data", systemImage: "chart.xyaxis.line", description: Text("Import a JSON file to view the market data."))
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
                if cursorX != nil {
                    ToolbarItem(placement: .automatic) {
                        Button("Cut Left") {
                            horizontalBounds.0 = cursorX
                        }
                    }
                    ToolbarItem(placement: .automatic) {
                        Button("Cut Right") {
                            horizontalBounds.1 = cursorX
                        }
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Button("Reset") {
                        horizontalBounds = (nil, nil)
                        verticalBoundsPerChart.removeAll()
                        cursorX = nil
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

        Task.detached(priority: .userInitiated) {
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let data = try Data(contentsOf: url)
                let decodedMessage = try JSONDecoder().decode(Message.self, from: data)

                // Collect all partial keys
                var allKeys = Set<String>()
                for chart in decodedMessage.charts {
                    for name in chart.data.keys {
                        allKeys.insert(partialKey(from: name))
                    }
                }

                // Update UI on main thread
                await MainActor.run {
                    self.horizontalBounds = (nil, nil)
                    self.verticalBoundsPerChart.removeAll()
                    self.partialKeyColors = PartialKeyColors()
                    self.partialKeyColors.buildColors(for: allKeys.sorted())
                    self.enabledPartialKeys = allKeys
                    self.message = decodedMessage
                }

            } catch {
                print("Error decoding: \(error)")
            }
        }
    }
}

#Preview {
    ContentView()
}
