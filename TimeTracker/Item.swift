//
//  Item.swift
//  TimeTracker
//
//  Created by Eugene Chan on 3/9/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
