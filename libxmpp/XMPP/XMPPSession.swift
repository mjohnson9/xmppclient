//
//  XMPPSession.swift
//  xmppclient
//
//  Created by Michael Johnson on 11/21/18.
//  Copyright © 2018 Michael Johnson. All rights reserved.
//

import Foundation

class XMPPSession: NSObject {
    struct Features {
        var tls: Bool = false
    }
    
    struct RequestsMade {
        var endStream: Bool = false
        var startTls: Bool = false
    }
    
    var features: Features = Features()
    var requestsMade: RequestsMade = RequestsMade()
    var receivedStreamStart: Bool = false
    var openingStreamQualifiedName: String!

    var currentElement: Element!
    var namespacesForElement: Dictionary<String, String>!
    var namespacePrefixes: Dictionary<String, [String]> = [:]
}
