//
//  ContentView.swift
//  visibag
//
//  Created by Alex A on 4/10/2024.
//

import SwiftUI
import Charts
import OrderedCollections

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
    let direction: Int
    let orderSize: Int
    let fillSize: Int
    
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
    var message: Message {
        let noData = OrderedDictionary<String, [Point]>()
        do {
            let messages = try JSONDecoder().decode([Message].self, from: Data(json.utf8))
            if let message = messages.first {
                return message
            }
            return Message(key: "Unknown", data: noData, events:[])
        }
        catch
        {
            print("Unexpected error: \(error).")
        }

        return Message(key: "Unknown", data: noData, events:[])
    }
    
    var horizontalDomain: ClosedRange<Double> {
        return domain(axis: .Horizontal)
    }
    
    var verticalDomain: ClosedRange<Double> {
        return domain(axis: .Vertical)
    }
    
    var body: some View {
        Chart (message.data.elements, id: \.key) { (name, series) in
            ForEach (series) { point in
                LineMark(
                    x: .value("Time", point.x),
                    y: .value("Value", point.y)
                )
            }
            .foregroundStyle(by: .value("Name", name))
            .interpolationMethod(.stepEnd)
        }
        .chartYScale(domain: verticalDomain)
        .chartXScale(domain: horizontalDomain)
        .chartYAxisLabel("Price")
        .chartXAxisLabel("Time")
        .chartOverlay { proxy in
            ZoomingOverlay(proxy: proxy, bounds: $bounds)
        }
        .navigationTitle("Visibag")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("Reset Zoom") {
                    bounds.removeAll()
                }
            }
        }
        .padding()
    }
    
    @State var bounds: Dictionary<AxisType, (Double?, Double?)> = Dictionary()
    
    func domain(axis: AxisType) -> ClosedRange<Double> {
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
        return min!...max!
    }
}

#Preview {
    ContentView()
}
