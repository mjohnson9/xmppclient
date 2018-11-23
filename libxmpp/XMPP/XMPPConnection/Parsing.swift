//
//  Parsing.swift
//  xmppclient
//
//  Created by Michael Johnson on 11/23/18.
//  Copyright © 2018 Michael Johnson. All rights reserved.
//

import Foundation

private struct AssociatedKeys {
    static var parserNeedsReset: UInt8 = 0
}

extension XMPPConnection: XMLParserDelegate {
    // MARK: Variables
    internal private(set) var parserNeedsReset: Bool {
        get {
            guard let value = objc_getAssociatedObject(self, &AssociatedKeys.parserNeedsReset) as? Bool else {
                return false
            }
            return value
        }
        set(newValue) {
            objc_setAssociatedObject(self, &AssociatedKeys.parserNeedsReset, newValue, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    internal func resetParser() {
        self.parserNeedsReset = true
    }
    
    internal func parserHasReset() {
        self.parserNeedsReset = false
    }
    
    // MARK: Parser delegate functions
    
    public func parser(_: XMLParser, didStartMappingPrefix: String, toURI: String) {
        var namespaceURIs = self.session!.namespacePrefixes[didStartMappingPrefix]
        if(namespaceURIs == nil) {
            namespaceURIs = []
        }
        namespaceURIs!.append(toURI)
        self.session!.namespacePrefixes[didStartMappingPrefix] = namespaceURIs
        
        if(didStartMappingPrefix.count > 0) {
            if(self.session!.namespacesForElement == nil) {
                self.session!.namespacesForElement = [:]
            }
            
            self.session!.namespacesForElement[didStartMappingPrefix] = toURI
        }
    }
    
    public func parser(_: XMLParser, didEndMappingPrefix: String) {
        if(self.parserNeedsReset) {
            // The parser calls this delegate during TLS negotiation for some reason
            return
        }
        
        var namespaceURIs = self.session!.namespacePrefixes[didEndMappingPrefix]
        if(namespaceURIs == nil) {
            print("\(self.domain): End of unknown namespace prefix: \(didEndMappingPrefix)")
            self.sendStreamErrorAndClose(tag: "invalid-xml")
            return
        }
        namespaceURIs!.remove(at: namespaceURIs!.count - 1)
        if(namespaceURIs!.count == 0) {
            self.session!.namespacePrefixes.removeValue(forKey: didEndMappingPrefix)
        } else {
            self.session!.namespacePrefixes[didEndMappingPrefix] = namespaceURIs
        }
    }
    
    public func parser(_: XMLParser, didStartElement: String, namespaceURI: String?, qualifiedName: String?, attributes: [String : String] = [:]) {
        let element: Element = Element()
        element.tag = didStartElement
        if(qualifiedName != nil) {
            let components = qualifiedName!.components(separatedBy: ":")
            switch(components.count) {
            case 1:
                let defaultNamespaces = self.session!.namespacePrefixes[""]
                if(defaultNamespaces == nil || defaultNamespaces!.count == 0) {
                    element.resolvedNamespace = ""
                    break
                }
                element.resolvedNamespace = defaultNamespaces![defaultNamespaces!.count - 1]
                break
            case 2:
                let namespacePrefix = components[0]
                let namespaceURIs = self.session!.namespacePrefixes[namespacePrefix]
                if(namespaceURIs == nil || namespaceURIs!.count == 0) {
                    print("\(self.domain): Encountered undefined namespace prefix: \(namespacePrefix)")
                    self.sendStreamErrorAndClose(tag: "bad-format")
                    return
                }
                let namespaceURI = namespaceURIs![namespaceURIs!.count - 1]
                element.prefix = namespacePrefix
                element.resolvedNamespace = namespaceURI
                break
            default:
                print("\(self.domain): Encountered tag with odd number of prefixes: \(components)")
                self.sendStreamErrorAndClose(tag: "bad-format")
                return
            }
        }
        
        let defaultNamespaces = self.session!.namespacePrefixes[""]
        if(defaultNamespaces != nil && defaultNamespaces!.count > 0) {
            element.defaultNamespace = defaultNamespaces![defaultNamespaces!.count - 1]
        }
        
        if(self.session!.namespacesForElement != nil) {
            element.prefixedNamespaces = self.session!.namespacesForElement
            self.session!.namespacesForElement = nil
        }
        
        element.attributes.reserveCapacity(attributes.count)
        for (name, value) in attributes {
            element.attributes[name] = value
        }
        
        element.parent = self.session.currentElement
        if(element.parent != nil) {
            element.parent.children.append(element)
        }
        if(element.resolvedNamespace == "http://etherx.jabber.org/streams" && element.tag == "stream" && element.parent == nil) {
            if(self.session!.openingStreamQualifiedName != nil) {
                // The stream opening was sent, but we've already received a stream open
                print("\(self.domain): Received a second stream opening")
                self.sendStreamErrorAndClose(tag: "invalid-xml")
                return
            }
            
            self.session!.openingStreamQualifiedName = qualifiedName
            receivedStreamStart(stanza: element)
            return
        }
        
        self.session.currentElement = element
    }
    
    public func parser(_: XMLParser, didEndElement: String, namespaceURI: String?, qualifiedName: String?) {
        if(didEndElement != self.session.currentElement.tag) {
            print("\(self.domain): Tag of ending element doesn't match element currently being processed: \(didEndElement) != \(self.session!.currentElement.tag)")
            self.sendStreamErrorAndClose(tag: "bad-format")
            return
        }
        
        if(self.session!.openingStreamQualifiedName != nil && qualifiedName == self.session!.openingStreamQualifiedName) {
            if(self.session!.currentElement != nil) {
                print("\(self.domain): Received stream closing inside of another element")
                self.sendStreamErrorAndClose(tag: "bad-format")
                return
            }
            
            self.session!.openingStreamQualifiedName = nil
            self.receivedStreamEnd()
            return
        }
        
        if(self.session!.currentElement.parent == nil) {
            self.receivedStanza(stanza: self.session.currentElement)
            if self.session != nil {
                // Sometimes, stanza handlers clear the session
                self.session.currentElement = nil
            }
            return
        }
        
        self.session!.currentElement = self.session!.currentElement.parent
    }
    
    public func parser(_: XMLParser, foundCharacters: String) {
        let trimmedString = foundCharacters.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        if(trimmedString.count == 0) {
            return
        }
        
        if(self.session!.currentElement == nil) {
            print("\(self.domain): Found characters outside of an element")
            self.sendStreamErrorAndClose(tag: "bad-format")
            return
        }
        
        self.session!.currentElement.contents = trimmedString
    }
}
