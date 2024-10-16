//
//  ContentView.swift
//  visibag
//
//  Created by Alex A on 4/10/2024.
//

import SwiftUI
import Charts

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


struct Message: Codable, Identifiable {
    let key: String
    let data: Dictionary<String, [Point]>
    let events: [String]
    
    var id: Int { key.hashValue }
}

struct NamedSeries : Identifiable
{
    let name: String
    let series: [Point]

    var id : Int { name.hashValue }
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
        return (extend(val: low, type: .Lower), extend(val: high, type: .Upper))
    }
    
    func extend(val: Double, type: BoundType) -> Double {
        let shouldReduce = ((type == .Lower) && (val >= 0.0)) || ((type == .Upper) && (val <= 0.0))
        return shouldReduce ? val * 0.9 : val * 1.1
    }
}

struct ContentView: View {
    var data: [NamedSeries] {
        do {
            let messages = try JSONDecoder().decode([Message].self, from: Data(json.utf8))
            if let message = messages.first {
                var result = [NamedSeries]()
                for (key, value) in message.data {
                    result.append(NamedSeries(name: key, series: value))
                }
                return result
            }
            return []
        }
        catch
        {
            print("Unexpected error: \(error).")
        }

        return []
    }
    
    var horizontalDomain: ClosedRange<Double> {
        return domain(axis: .Horizontal)
    }
    
    var verticalDomain: ClosedRange<Double> {
        return domain(axis: .Vertical)
    }
    
    var body: some View {
        Chart (data) { series in
            ForEach (series.series) { point in
                if horizontalDomain.contains(point.x) {
                LineMark(
                    x: .value("Time", point.x),
                    y: .value("Value", point.y)
                )
                }
            }
            .foregroundStyle(by: .value("Name", series.name))
            .interpolationMethod(.stepEnd)
        }
        .chartYScale(domain: verticalDomain)
        .chartXScale(domain: horizontalDomain)
        .chartYAxisLabel("Price")
        .chartXAxisLabel("Time")
        .chartOverlay { proxy in
            ZoomingOverlay(proxy: proxy, bounds: $bounds)
        }
        .padding()
    }
    
    @State var bounds: Dictionary<AxisType, (Double?, Double?)> = Dictionary()
    
    func domain(axis: AxisType) -> ClosedRange<Double> {
        var (min, max) = bounds[axis] ?? (nil, nil)
        if min == nil || max == nil {
            for (series) in data {
                for point in series.series {
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
