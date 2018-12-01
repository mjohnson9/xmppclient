//
//  Parsing.swift
//  xmppclient
//
//  Created by Michael Johnson on 11/23/18.
//  Copyright © 2018 Michael Johnson. All rights reserved.
//

import Foundation
import os.log

private struct AssociatedKeys {
    static var parserNeedsReset: UInt8 = 0
}

extension XMPPConnection: EventedXMLParserDelegate {
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

    /*public func parser(didStartMappingPrefix: String, toURI: String) {
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
            os_log(.info, log: XMPPConnection.osLog, "%s: Ended namespace %{public}s without ever starting it", self.domain, didEndMappingPrefix)
            self.sendStreamErrorAndClose(tag: "invalid-xml")
            return
        }
        namespaceURIs!.remove(at: namespaceURIs!.count - 1)
        if(namespaceURIs!.count == 0) {
            self.session!.namespacePrefixes.removeValue(forKey: didEndMappingPrefix)
        } else {
            self.session!.namespacePrefixes[didEndMappingPrefix] = namespaceURIs
        }
    }*/

    public func parser(didStartElement: String, namespaceURI: String?, prefix: String?, namespaces: [String: String], attributes: [String: String]) {
        let element: Element = Element()
        element.tag = didStartElement
        let qualifiedName = (prefix != nil ? prefix! + ":" : "") + didStartElement

        if let prefix = prefix {
            guard let namespaceURIs = self.session!.namespacePrefixes[prefix], namespaceURIs.count > 0 else {
                os_log(.info, log: XMPPConnection.osLog, "%s: Element has namespace prefix of %{public}s, but the server never defined that prefix", self.domain, prefix)
                self.sendStreamErrorAndClose(tag: "bad-format")
                return
            }
            let namespaceURI = namespaceURIs[namespaceURIs.count - 1]
            element.prefix = prefix
            element.resolvedNamespace = namespaceURI
        }

        let defaultNamespaces = self.session!.namespacePrefixes[""]
        if defaultNamespaces != nil && defaultNamespaces!.count > 0 {
            element.defaultNamespace = defaultNamespaces![defaultNamespaces!.count - 1]
        }

        if self.session!.namespacesForElement != nil {
            element.prefixedNamespaces = self.session!.namespacesForElement
            self.session!.namespacesForElement = nil
        }

        element.attributes.reserveCapacity(attributes.count)
        for (name, value) in attributes {
            element.attributes[name] = value
        }

        element.parent = self.session.currentElement
        if element.parent != nil {
            element.parent.children.append(element)
        }
        if element.resolvedNamespace == "http://etherx.jabber.org/streams" && element.tag == "stream" && element.parent == nil {
            if self.session!.openingStreamQualifiedName != nil {
                // The stream opening was sent, but we've already received a stream open
                os_log(.info, log: XMPPConnection.osLog, "%s: Received a second stream opening", self.domain)
                self.sendStreamErrorAndClose(tag: "invalid-xml")
                return
            }

            self.session!.openingStreamQualifiedName = qualifiedName
            receivedStreamStart(stanza: element)
            return
        }

        self.session.currentElement = element
    }

    public func parser(didEndElement: String, namespaceURI: String?, prefix: String?) {
        if didEndElement != self.session.currentElement.tag {
            os_log(.info, log: XMPPConnection.osLog, "%s: Tag of ending element doesn't match element currently being processed: %{public}s != %{public}s", self.domain, didEndElement, self.session!.currentElement.tag)
            self.sendStreamErrorAndClose(tag: "bad-format")
            return
        }
        let qualifiedName = (prefix != nil ? prefix! + ":" : "") + didEndElement

        if self.session!.openingStreamQualifiedName != nil && qualifiedName == self.session!.openingStreamQualifiedName {
            guard self.session!.currentElement == nil else {
                os_log(.info, log: XMPPConnection.osLog, "%s: Received stream closing inside of another element", self.domain)
                self.sendStreamErrorAndClose(tag: "bad-format")
                return
            }

            self.session!.openingStreamQualifiedName = nil
            self.receivedStreamEnd()
            return
        }

        if self.session!.currentElement.parent == nil {
            self.receivedStanza(stanza: self.session.currentElement)
            if self.session != nil {
                // Sometimes, stanza handlers clear the session
                self.session.currentElement = nil
            }
            return
        }

        self.session!.currentElement = self.session!.currentElement.parent
    }

    public func parser(foundCharacters: String) {
        let trimmedString = foundCharacters.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        if trimmedString.count == 0 {
            return
        }

        guard let currentElement = self.session!.currentElement else {
            os_log(.info, log: XMPPConnection.osLog, "%s: Received text node as a child of the root node", self.domain)
            self.sendStreamErrorAndClose(tag: "bad-format")
            return
        }

        if currentElement.contents == nil {
            currentElement.contents = trimmedString
        } else {
            currentElement.contents += trimmedString
        }
    }

    public func parser(foundCDATA: Data) {
        guard let currentElement = self.session!.currentElement else {
            os_log(.info, log: XMPPConnection.osLog, "%s: Received CDATA as a child of the root node", self.domain)
            self.sendStreamErrorAndClose(tag: "bad-format")
            return
        }

        guard let decodedCDATA = String(data: foundCDATA, encoding: .utf8) else {
            os_log(.info, log: XMPPConnection.osLog, "%s: Received CDATA that could not be decoded as UTF-8")
            self.sendStreamErrorAndClose(tag: "unsupported-encoding")
            return
        }

        if currentElement.contents == nil {
            currentElement.contents = decodedCDATA
        } else {
            currentElement.contents += decodedCDATA
        }
    }

    // MARK: Fatal stream errors because of parsing

    public func parser(resolveExternalEntityName: String, systemID: String?) -> Data? {
        os_log(.info, log: XMPPConnection.osLog, "%s: Received XML external entity", self.domain)
        self.sendStreamErrorAndClose(tag: "restricted-xml")
        return nil
    }

    public func parser(foundProcessingInstructionWithTarget: String, data: String?) {
        os_log(.info, log: XMPPConnection.osLog, "%s: Received XML processing instruction", self.domain)
        self.sendStreamErrorAndClose(tag: "restricted-xml")
    }

    public func parser(foundComment: String) {
        os_log(.info, log: XMPPConnection.osLog, "%s: Received XML comment", self.domain)
        self.sendStreamErrorAndClose(tag: "restricted-xml")
    }

    public func parser(parseErrorOccurred: Error) {
        switch parseErrorOccurred {
        case let castedError as NSError:
            os_log(.info, log: XMPPConnection.osLog, "%s: Error parsing XML stream: %@", self.domain, castedError)
        case let castedError as XMLParsingError:
            os_log(.info, log: XMPPConnection.osLog, "%s: Error parsing XML stream: %s", self.domain, castedError.message)
        default:
            os_log(.info, log: XMPPConnection.osLog, "%s: Error parsing XML stream: (unknown type)", self.domain)
        }
        self.sendStreamErrorAndClose(tag: "bad-format")
    }
}
