//
//  SRVRecord.swift
//  xmppclient
//
//  Created by Michael Johnson on 11/22/18.
//  Copyright © 2018 Michael Johnson. All rights reserved.
//

import Foundation

class SRVRecord: NSObject {
    var target: String
    var port: UInt16
    var priority: UInt16
    var weight: UInt16
    internal var weightForShuffle: Float
    
    init(dict: NSDictionary) {
        self.target = dict[kSRVResolverTarget] as! String
        self.port = UInt16(dict[kSRVResolverPort] as! Int64)
        self.priority = UInt16(dict[kSRVResolverPriority] as! Int64)
        self.weight = UInt16(dict[kSRVResolverWeight] as! Int64)
        
        self.weightForShuffle = Float.random(in: 0..<1) * (1.0 / Float(self.weight))
    }
    
    static func shuffle(records: inout [SRVRecord]) {
        records.sort(by: SRVRecord.compare)
    }
    
    internal static func compare(recordOne: SRVRecord, recordTwo: SRVRecord) -> Bool {
        if(recordOne.priority != recordTwo.priority) {
            return recordOne.priority < recordTwo.priority
        }
        
        return recordOne.weightForShuffle < recordTwo.weightForShuffle
    }
}
