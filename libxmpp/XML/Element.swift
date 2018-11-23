//
//  Element.swift
//  xmppclient
//
//  Created by Michael Johnson on 11/21/18.
//  Copyright © 2018 Michael Johnson. All rights reserved.
//

import Foundation

class Element: NSObject {
    var prefix: String = ""
    var tag: String = ""
    var resolvedNamespace: String!
    var defaultNamespace: String!
    var prefixedNamespaces: Dictionary<String, String> = [:]
    var parent: Element!
    var attributes: Dictionary<String, String> = [:]
    var children: [Element] = []
    var contents: String!
    
    public func serialize() -> String {
        let returnString: NSMutableString = "<"
        if(self.prefix.count > 0) {
            returnString.append("\(self.prefix):")
        }
        returnString.append(self.tag)
        
        if(self.defaultNamespace != nil) {
            returnString.append(" xmlns='\(Element.escapeAttribute(self.defaultNamespace))'")
        }
        
        for (prefix, namespaceURI) in self.prefixedNamespaces {
            returnString.append(" xmlns:\(prefix)='\(Element.escapeAttribute(namespaceURI))'")
        }
        
        for (name, value) in self.attributes {
            returnString.append(" \(name)='\(Element.escapeAttribute(value))'")
        }
        
        var shortClose: Bool = true
        
        if(self.contents != nil && self.contents.count > 0) {
            returnString.append(self.contents)
            shortClose = false
        }
        
        if(self.children.count > 0) {
            returnString.append(">")
            for child in self.children {
                returnString.append(child.serialize())
            }
            shortClose = false
        }
        
        if(shortClose) {
            returnString.append("/>")
        } else {
            returnString.append("<\(self.tag)/>")
        }
        
        return returnString as String
    }
    
    internal static func escapeAttribute(_ value: String) -> NSMutableString {
        let mutable = NSMutableString(string: value)
        mutable.replacingOccurrences(of: "&", with: "&amp;")
        mutable.replacingOccurrences(of: "\"", with: "&quot;")
        mutable.replacingOccurrences(of: "'", with: "&#39;")
        mutable.replacingOccurrences(of: ">", with: "&gt;")
        mutable.replacingOccurrences(of: "<", with: "&lt;")
        return mutable
    }
}
