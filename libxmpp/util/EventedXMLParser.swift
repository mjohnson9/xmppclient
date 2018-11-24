//
//  EventedXMLParser.swift
//  xmppclient
//
//  Created by Michael Johnson on 11/24/18.
//  Copyright © 2018 Michael Johnson. All rights reserved.
//

import Foundation
import libxml2

/*class EventedXMLParser {
    public var delegate: EventedXMLParserDelegate?
    
    private let xmlParserContext: xmlParserCtxtPtr
    
    init() {
        self.xmlParserContext = xmlCreatePushParserCtxt(<#T##sax: xmlSAXHandlerPtr!##xmlSAXHandlerPtr!#>, <#T##user_data: UnsafeMutableRawPointer!##UnsafeMutableRawPointer!#>, <#T##chunk: UnsafePointer<Int8>!##UnsafePointer<Int8>!#>, <#T##size: Int32##Int32#>, <#T##filename: UnsafePointer<Int8>!##UnsafePointer<Int8>!#>)
    }
    
    private func createSaxHandler() -> xmlSAXHandlerPtr! {
        let saxHandler: xmlSAXHandler = xmlDefaultSAXHandlerInit()
        saxHandler.
    }
    
    public func feed(_ data: Data) {
        
    }
}*/

protocol EventedXMLParserDelegate {
    
}
