//
//  ContentView.swift
//  visibag
//
//  Created by Alex A on 4/10/2024.
//

import SwiftUI
import Charts

struct Point : Identifiable {
    let x: Float
    let y: Float
    
    var id: Int { x.hashValue }
}

struct ContentView: View {
    let points = [Point](arrayLiteral: Point(x: 0, y: 1), Point(x: 1, y: 2), Point(x: 2, y: 3))
    
    var body: some View {
        Chart (points) { point in
            LineMark(
                x: .value("Time", point.x),
                y: .value("Value", point.y)
            )
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
