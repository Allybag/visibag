//
//  ContentView.swift
//  visibag
//
//  Created by Alex A on 4/10/2024.
//

import SwiftUI
import Charts

struct Point : Codable, Identifiable {
    let x: Float
    let y: Float

    var id: Int { x.hashValue }

    init(from decoder: Decoder) throws {
        var values = try decoder.unkeyedContainer()
        x = try values.decode(Float.self)
        y = try values.decode(Float.self)
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

struct ContentView: View {
    var data: [NamedSeries] {
        do {
            let messages = try JSONDecoder().decode([Message].self, from: Data(json.utf8))
            print("Mesaages: \(messages)")
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

    var body: some View {
        Chart (data) { series in
            ForEach (series.series) { point in
                LineMark(
                    x: .value("Time", point.x),
                    y: .value("Value", point.y)
                )
            }
            .foregroundStyle(by: .value("Name", series.name))
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXScale(domain: .automatic(includesZero: false))
        .chartYAxisLabel("Price")
        .chartXAxisLabel("Time")
        .padding()
    }
}

#Preview {
    ContentView()
}
