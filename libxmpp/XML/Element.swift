//
//  Element.swift
//  xmppclient
//
//  Created by Michael Johnson on 11/21/18.
//  Copyright © 2018 Michael Johnson. All rights reserved.
//

import Foundation

/// An XML element
class Element: NSObject {
    /// The namespace prefix of the element
    var prefix: String = ""
    /// The element's tag
    var tag: String = ""
    /// The namespace that the element resolved to.
    /// This is not needed for creating elements, it's only used by the parser.
    var resolvedNamespace: String!
    /// The default namespace of the element (corresponds to XML's xmlns)
    var defaultNamespace: String!
    /// The prefixed namespaces of the element (corresponds to XML's xmlns:key=value)
    var prefixedNamespaces: [String: String] = [:]
    /// The element's parent element. Root elements will have a nil parent.
    var parent: Element!
    /// The element's XML attributes
    ///
    /// For xmlns and xmlns:key, see defaultNamespace and prefixedNamespaces respectively.
    var attributes: [String: String] = [:]
    /// The child elements of this element, in order.
    var children: [Element] = []
    /// The text node of this element
    var contents: String!

    /// Serializes an Element and its children into a valid XML string
    ///
    /// - Returns: An XML string representing the Element
    public func serialize() -> String {
        let returnString: NSMutableString = "<"
        if self.prefix.count > 0 {
            returnString.append("\(self.prefix):")
        }
        returnString.append(self.tag)

        if self.defaultNamespace != nil {
            returnString.append(" xmlns='\(Element.escapeAttribute(self.defaultNamespace))'")
        }

        for (prefix, namespaceURI) in self.prefixedNamespaces {
            returnString.append(" xmlns:\(prefix)='\(Element.escapeAttribute(namespaceURI))'")
        }

        for (name, value) in self.attributes {
            returnString.append(" \(name)='\(Element.escapeAttribute(value))'")
        }

        var shortClose: Bool = true

        if self.contents != nil && self.contents.count > 0 {
            if shortClose {
                returnString.append(">")
                shortClose = false
            }
            returnString.append(self.contents)
        }

        if self.children.count > 0 {
            if shortClose {
                returnString.append(">")
                shortClose = false
            }
            for child in self.children {
                returnString.append(child.serialize())
            }
        }

        if shortClose {
            returnString.append("/>")
        } else {
            returnString.append("<\(self.tag)/>")
        }

        return returnString as String
    }

    /// Escapes a string for use in an XML attribute
    ///
    /// - Parameter value: The string to be escaped
    /// - Returns: The string with special characters escaped
    public static func escapeAttribute(_ value: String) -> NSMutableString {
        let mutable = NSMutableString(string: value)
        mutable.replacingOccurrences(of: "&", with: "&amp;")
        mutable.replacingOccurrences(of: "\"", with: "&quot;")
        mutable.replacingOccurrences(of: "'", with: "&#39;")
        mutable.replacingOccurrences(of: ">", with: "&gt;")
        mutable.replacingOccurrences(of: "<", with: "&lt;")
        return mutable
    }
}
