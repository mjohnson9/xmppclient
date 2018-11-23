//
//  xmppconnection.swift
//  xmppclient
//
//  Created by Michael Johnson on 11/21/18.
//  Copyright © 2018 Michael Johnson. All rights reserved.
//

import Foundation
import Network

class XMPPConnection : NSObject, SRVResolverDelegate, XMLParserDelegate, StreamDelegate {
    var domain: String = ""
    private var srvName: String {
        get {
            return "_xmpp-client._tcp." + self.domain
        }
    }
    
    private var connectionAddresses: [(host: String, port: UInt16)]!
    private var currentConnectionAddress: Int = 0
    private var attemptReconnect: Bool = true
    private var allInsecure: Bool = true
    private var allowInsecure: Bool = false
    
    private var inStream: InputStream!
    private var outStream: OutputStream!
    
    private var readThread: Thread!
    
    private var resolver: SRVResolver!
    private var resolverTimer: Timer!
    
    private var session: XMPPSession!
    private var parserNeedsReset: Bool = false
    
    private var connectionObservers: [XMPPConnectionObserver] = []
    
    init(forDomain domain: String, allowInsecure: Bool) {
        self.domain = domain
        self.allowInsecure = allowInsecure
        if(self.allowInsecure) {
            // Don't send a message about insecure servers if they allow insecure servers
            self.allInsecure = false
        }
    }
    
    public func connect() {
        print("Connecting to \(self.domain)")
        // Start by attempting to resolve SRV records
        self.resolveSRV()
    }
    
    public func disconnect() {
        self.disconnectWithoutRetry()
    }
    
    internal func disconnectWithoutRetry() {
        self.attemptReconnect = false
        self.disconnectAndRetry()
    }
    
    internal func disconnectAndRetry() {
        self.session = nil
        
        if(self.inStream != nil) {
            self.inStream.close()
            self.inStream = nil
        }
        
        if(self.outStream != nil) {
            self.outStream.close()
            self.outStream = nil
        }
    }
    
    public func addConnectionObserver(observer: XMPPConnectionObserver) -> Int {
        self.connectionObservers.append(observer)
        return self.connectionObservers.count - 1
    }
    
    public func removeConnectionObserver(observer: Int) {
        self.connectionObservers.remove(at: observer)
    }
    
    internal func _connect() {
        self.readThread = Thread(target: self, selector: #selector(self.readThreadMain), object: nil)
        self.readThread.name = "XMPP receiving: \(self.domain)"
        self.readThread.start()
    }
    
    @objc internal func readThreadMain() {
        if(self.connectionAddresses == nil) {
            self.dispatchCannotConnect(error: XMPPUnableToConnectError())
            return
        }
        
        while(self.attemptReconnect) {
            if(self.currentConnectionAddress > (self.connectionAddresses.count - 1)) {
                print("\(self.domain): Ran out of hosts to connect to")
                if(self.allInsecure) {
                    self.dispatchCannotConnect(error: XMPPCriticalSSLError())
                } else {
                    self.dispatchCannotConnect(error: XMPPUnableToConnectError())
                }
                return
            }
            
            let connectionAddress = self.connectionAddresses[self.currentConnectionAddress]
            self.currentConnectionAddress += 1
            
            let error = self.attemptConnection(toHostname: connectionAddress.host, toPort: connectionAddress.port)
            let nsError = error as NSError?
            if(nsError != nil) {
                print("\(self.domain): Disconnected from \(connectionAddress.host):\(connectionAddress.port) with error: (\(nsError!.domain):\(nsError!.code)) \(nsError!.localizedDescription) | \(nsError!.localizedFailureReason)")
            } else if(error != nil) {
                print("\(self.domain): Disconnected from \(connectionAddress.host):\(connectionAddress.port) with error: (\(String(describing: error))")
            } else {
                print("\(self.domain): Disconnected from \(connectionAddress.host):\(connectionAddress.port)")
            }
        }
    }
    
    internal func dispatchConnected(status: XMPPConnectionStatus) {
        for connectionObserver in self.connectionObservers {
            connectionObserver.xmppConnected(connectionStatus: status)
        }
    }
    
    internal func dispatchCannotConnect(error: Error) {
        for connectionObserver in self.connectionObservers {
            connectionObserver.xmppCannotConnect(error: error)
        }
    }
    
    internal func receivedStreamStart(stanza: Element) {
        let versionAttribute = stanza.attributes["version"]
        if(versionAttribute == nil) {
            // Version is a required attribute
            print("\(self.domain) Stream start is missing version attribute")
            self.sendStreamErrorAndClose(tag: "invalid-xml")
            return
        }
        let version = self.getVersion(versionAttribute!)
        if(version.major != 1 || version.minor != 0) {
            print("\(self.domain) Server version is unsupported:", versionAttribute!)
            self.sendStreamErrorAndClose(tag: "unsupported-version")
            return
        }
        
        if(self.session.secure) {
            self.allInsecure = false
        }
        
        print("\(self.domain): Received start of stream")
    }
    
    internal func getVersion(_ version: String) -> (major: Int, minor: Int) {
        let splitVersion = version.components(separatedBy: ".")
        if(splitVersion.count != 2) {
            return (major: 0, minor: 0)
        }
        
        let major = Int(splitVersion[0])
        if(major == nil) {
            return (major: 0, minor: 0)
        }
        
        let minor = Int(splitVersion[1])
        if(minor == nil) {
            return (major: 0, minor: 0)
        }
        
        return (major: major!, minor: minor!)
    }
    
    internal func receivedStreamEnd() {
        if(!self.session.requestsMade.endStream) {
            self.write(string: "</stream:stream>")
        }
        
        self.disconnectAndRetry()
    }
    
    internal func receivedStanza(stanza: Element) {
        #if DEBUG
        print("\(self.domain) ->", stanza.serialize())
        #endif
        switch(stanza.resolvedNamespace) {
        case "http://etherx.jabber.org/streams":
            return self.processStreamsNamespace(stanza: stanza)
        case "urn:ietf:params:xml:ns:xmpp-tls":
            return self.processTlsNamespace(stanza: stanza)
        default:
            print("\(self.domain): Unable to handle stanza from namespace", stanza.resolvedNamespace)
            self.sendStreamErrorAndClose(tag: "unsupported-stanza-type")
            return
        }
    }
    
    internal func processStreamsNamespace(stanza: Element) {
        switch(stanza.tag) {
        case "features":
            return self.processFeatures(stanza: stanza)
        case "error":
            return self.processErrors(stanza: stanza)
        default:
            print("\(self.domain): Unable to handle stanza with tag", stanza.tag, "in namespace", stanza.resolvedNamespace)
            self.sendStreamErrorAndClose(tag: "unsupported-stanza-type")
            return
        }
    }
    
    internal func processErrors(stanza: Element) {
        var errorTag: String = ""
        var errorContents: String?
        var textContent: Dictionary<String, String> = [:]
        for child in stanza.children {
            if(child.resolvedNamespace == "urn:ietf:params:xml:ns:xmpp-streams") {
                if(child.tag == "text") {
                    var lang = ""
                    let langAttribute = child.attributes["xml:lang"]
                    if(langAttribute != nil) {
                        lang = langAttribute!
                    }
                    if(child.contents != nil) {
                        textContent[lang] = child.contents!
                    }
                } else {
                    errorTag = child.tag
                    errorContents = child.contents
                }
            }
        }
        
        switch(errorTag) {
        case "host-gone", "host-unknown":
            // This XMPP server doesn't host the given domain
            let attemptedConnectionAddress = self.connectionAddresses[self.currentConnectionAddress]
            print("\(self.domain): Received \(errorTag) error from \(attemptedConnectionAddress.host):\(attemptedConnectionAddress.port)")
            self.disconnectAndRetry()
            return
        case "see-other-host":
            if(errorContents == nil) {
                print("\(self.domain): Received see-other-host error with no host specified")
                self.disconnectAndRetry()
                return
            }
            
            let newHost = errorContents!
            print("\(self.domain): Got referral to another host:", newHost)
            
            let portIndex = newHost.lastIndex(of: ":")
            var host = newHost
            var port: UInt16 = 5222
            if(portIndex != nil) {
                let afterColonIndex = portIndex!.encodedOffset + 1
                let portStr = newHost.suffix(afterColonIndex)
                let portNum = UInt16(portStr)
                if(portNum != nil) { // Parsing will fail if this is the end of an IPv6 address. That's deliberate.
                    port = portNum!
                    host = String(newHost.prefix(upTo: portIndex!))
                }
            }
            
            var alreadyExists: Bool = false // If we've already tried this referral, don't try again
            for address in self.connectionAddresses {
                if(address.host == host && address.port == port) {
                    alreadyExists = true
                }
            }
            if(!alreadyExists) {
                self.connectionAddresses.insert((host: host, port: port), at: self.currentConnectionAddress) // Make the next connection attempt use the given host
            }
            self.disconnectAndRetry()
            return
        default:
            // Switch has to be exhaustive
            self.disconnectAndRetry()
            return
        }
    }
    
    internal func processTlsNamespace(stanza: Element) {
        switch(stanza.tag) {
        case "proceed":
            if(!self.session!.requestsMade.startTls) {
                print("\(self.domain): Server sent StartTLS proceed without being asked")
                self.sendStreamErrorAndClose(tag: "invalid-xml")
                return
            }
            
            self.enableTls()
            return
        case "failure":
            if(!self.session!.requestsMade.startTls) {
                print("\(self.domain): Server sent StartTLS failure without being asked")
                self.sendStreamErrorAndClose(tag: "invalid-xml")
                return
            }
            
            self.disconnectAndRetry()
            return
        default:
            print("\(self.domain): Unable to handle stanza with tag", stanza.tag, "in namespace", stanza.resolvedNamespace)
            self.sendStreamErrorAndClose(tag: "unsupported-stanza-type")
            return
        }
    }
    
    internal func processFeatures(stanza: Element) {
        for child in stanza.children {
            let feature = self.createFeature(child)
            self.session.features.append(feature)
        }
        
        self.negotiateNextFeature()
    }
    
    internal func negotiateNextFeature() {
        var anyRequired: Bool = false
        var nextNegotiable: Element!
        var negotiablePriority: Int = 0
        
        for feature in self.session.features {
            switch(feature.namespace) {
            case "urn:ietf:params:xml:ns:xmpp-tls":
                if(feature.name == "starttls") {
                    if(!self.session.secure) {
                        if(nextNegotiable == nil || (feature.required && negotiablePriority < 1000) || (!feature.required && !anyRequired && negotiablePriority < 1000)) {
                            nextNegotiable = feature.stanza
                            anyRequired = feature.required
                            negotiablePriority = 1000
                        }
                    } else {
                        print("\(self.domain) Received TLS offer inside of a secure session")
                    }
                }
                break
            default:
                if(!anyRequired && feature.required) {
                    anyRequired = true
                }
                /*for child in feature.children {
                    if(child.tag == "required") {
                        print("\(self.domain): \(feature.resolvedNamespace) -> \(feature.tag) is required and we don't know how to negotiate it")
                        anyRequired = true
                    }
                }
                
                print("\(self.domain): Encountered unknown feature: \(feature.resolvedNamespace) -> \(feature.tag)")*/
                break
            }
        }
        
        if(anyRequired && nextNegotiable == nil) {
            print("\(self.domain): We don't support any of the required features. Disconnecting.")
            self.sendStreamErrorAndClose(tag: "unsupported-feature")
            return self.dispatchCannotConnect(error: XMPPIncompatibleError())
        }
        
        if(nextNegotiable != nil) {
            if(nextNegotiable.resolvedNamespace == "urn:ietf:params:xml:ns:xmpp-tls" && nextNegotiable.tag == "starttls") {
                return self.negotiateTLS()
            } else {
                fatalError("\(self.domain): Chose feature for negotiation that we don't support: \(nextNegotiable.resolvedNamespace) -> \(nextNegotiable.tag)")
            }
        } else {
            print("\(self.domain): Negotiation finished.")
        }
    }
    
    internal func createFeature(_ stanza: Element) -> XMPPSession.Feature {
        var feature = XMPPSession.Feature(namespace: stanza.resolvedNamespace, name: stanza.tag, required: false, stanza: stanza)
        
        for child in stanza.children {
            if(child.tag == "required") {
                feature.required = true
            }
        }
        
        return feature
    }
    
    func parser(_: XMLParser, didStartMappingPrefix: String, toURI: String) {
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
    
    func parser(_: XMLParser, didEndMappingPrefix: String) {
        if(self.parserNeedsReset) {
            // For some reason, the parser calls this during the TLS handshake
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
    
    func parser(_: XMLParser, didStartElement: String, namespaceURI: String?, qualifiedName: String?, attributes: [String : String] = [:]) {
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
    
    func parser(_: XMLParser, didEndElement: String, namespaceURI: String?, qualifiedName: String?) {
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
            self.session.currentElement = nil
            return
        }
        
        self.session!.currentElement = self.session!.currentElement.parent
    }
    
    func parser(_: XMLParser, foundCharacters: String) {
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
    
    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        switch(eventCode) {
        case Stream.Event.openCompleted:
            print("\(self.domain): \(aStream) is open")
            if(aStream == self.outStream) {
                self.sendStreamOpener()
            }
            break
        case Stream.Event.hasSpaceAvailable:
            #if DEBUG
            print("\(self.domain): \(aStream) has space available")
            #endif
            break
        case Stream.Event.hasBytesAvailable:
            #if DEBUG
            print("\(self.domain): \(aStream) has bytes available")
            #endif
        case Stream.Event.endEncountered:
            print("\(self.domain): \(aStream) encountered EOF")
        case Stream.Event.errorOccurred:
            print("\(self.domain): \(aStream) had an error: \(String(describing: aStream.streamError))")
        default:
            print("\(self.domain): Received unhandled event: \(eventCode)")
            break
        }
    }
    
    internal func negotiateTLS() {
        let element = Element()
        element.tag = "starttls"
        element.defaultNamespace = "urn:ietf:params:xml:ns:xmpp-tls"
        
        self.session!.requestsMade.startTls = true
        self.write(string: element.serialize())
    }
    
    internal func enableTls() {
        let sslSettings: Dictionary<NSString, Any> = [
            NSString(format: kCFStreamSSLLevel): kCFStreamSocketSecurityLevelNegotiatedSSL,
            NSString(format: kCFStreamSSLPeerName): NSString(string: self.domain)
        ]
        
        self.outStream.setProperty(sslSettings, forKey: kCFStreamPropertySSLSettings as Stream.PropertyKey)
        self.inStream.setProperty(sslSettings, forKey: kCFStreamPropertySSLSettings as Stream.PropertyKey)
        
        print("\(self.domain): Enabled TLS")
        
        self.parserNeedsReset = true
        self.session = XMPPSession()
        self.session!.secure = true
        self.sendStreamOpener()
    }
    
    internal func sendStreamOpener() {
        let openStream = "<?xml version='1.0'?><stream:stream to='\(self.domain)' version='1.0' xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams'>"
        self.write(string: openStream)
        print("\(self.domain): Sent stream opening")
    }
    
    internal func sendStreamErrorAndClose(tag: String) {
        let streamError  = self.constructStreamError(tag: tag)
        self.write(string: streamError)
        self.disconnectAndRetry()
        print("\(self.domain): Sent stream error:", tag)
    }
    
    internal func constructStreamError(tag: String) -> String {
        let root = Element()
        root.prefix = "stream"
        root.tag = "error"
        root.attributes["to"] = self.domain
        
        let child = Element()
        child.tag = tag
        child.defaultNamespace = "urn:ietf:params:xml:ns:xmpp-streams"
        
        root.children = [child]
        
        return root.serialize()
    }
    
    internal func write(string: String) {
        #if DEBUG
        print("\(self.domain) <-", string)
        #endif
        let encodedString: Data = string.data(using: .utf8)!
        encodedString.withUnsafeBytes {
            self.outStream.write($0, maxLength: encodedString.count)
        }
    }
    
    internal func attemptConnection(toHostname hostname: String, toPort port: UInt16) -> Error? {
        print("\(self.domain): Attempting connection to \(hostname):\(port)")
        
        self.session = XMPPSession()
        
        Stream.getStreamsToHost(withName: hostname, port: Int(port), inputStream: &self.inStream, outputStream: &self.outStream)
        
        self.inStream.delegate = self
        self.outStream.delegate = self
        
        DispatchQueue.global(qos: .background).async {
            self.outStream.schedule(in: RunLoop.current, forMode: .common)
            RunLoop.current.run()
        }
        
        self.inStream.setProperty(kCFBooleanTrue, forKey: kCFStreamPropertySocketExtendedBackgroundIdleMode as Stream.PropertyKey)
        self.outStream.setProperty(kCFBooleanTrue, forKey: kCFStreamPropertySocketExtendedBackgroundIdleMode as Stream.PropertyKey)
        
        self.inStream.open()
        self.outStream.open()
        
        
        var parser: XMLParser = XMLParser(stream: self.inStream)
        
        parser.shouldResolveExternalEntities = false
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = true
        
        parser.delegate = self
        
        var success: Bool = true
        while(success && self.inStream != nil) {
            success = parser.parse()
            
            if(self.parserNeedsReset && self.inStream != nil) {
                parser = XMLParser(stream: self.inStream)
                
                parser.shouldResolveExternalEntities = false
                parser.shouldProcessNamespaces = true
                parser.shouldReportNamespacePrefixes = true
                
                parser.delegate = self
                
                self.parserNeedsReset = false
            }
        }
        
        var error: Error? = nil
        if(self.inStream != nil) {
            error = self.inStream.streamError
        }
        
        self.disconnectAndRetry()
        
        return error
    }
    
    internal func resolveSRV() {
        print("\(self.domain): Resolving SRV records")
        self.resolver = SRVResolver(srvName: self.srvName)
        self.resolver.delegate = self
        self.resolver.start()
        
        self.resolverTimer = Timer(timeInterval: 1.0, target: self, selector: #selector(self.resolverTimeout), userInfo: nil, repeats: false)
        let runLoop = RunLoop.current
        runLoop.add(self.resolverTimer, forMode: RunLoop.Mode.common)
        runLoop.run()
    }
    
    internal func switchToFallbackDNS() {
        print("\(self.domain): Using fallback DNS")
        self.connectionAddresses = [(host: self.domain, port: UInt16(5222))]
        self._connect()
    }
    
    internal func handleSRVResults(results: [SRVRecord]!) {
        if(results == nil || results.count == 0) {
            self.switchToFallbackDNS()
            return
        }

        // Check for service not supported record
        if(results.count == 1) {
            let result = results[0]
            if(result.target == ".") {
                print("\(self.domain): Encountered SRV record with target of \".\". Service is unavailable for this domain.")
                self.dispatchCannotConnect(error: XMPPServiceNotSupportedError())
                return
            }
        }
        
        self.connectionAddresses = []
        self.connectionAddresses.reserveCapacity(results.count)
        for result in results {
            self.connectionAddresses.append((host: result.target, port: result.port))
        }
        
        self._connect()
    }
    
    internal func convertSRVRecords(results: [Any]!) -> [SRVRecord]? {
        if(results == nil || results.count == 0) {
            return nil
        }
        
        var converted: [SRVRecord] = []
        converted.reserveCapacity(results.count)
        
        for resultAny in results {
            let result = resultAny as! NSDictionary
            let record = SRVRecord(dict: result)
            converted.append(record)
        }
        
        SRVRecord.shuffle(records: &converted)
        
        return converted
    }
    
    internal func srvResolver(_ resolver: SRVResolver!, didStopWithError error: Error!) {
        self.resolverTimer.invalidate()
        self.resolverTimer = nil
        
        if(error != nil) {
            print("\(self.domain): Failed to resolve \(self.srvName): \(String(describing: error))")
            self.switchToFallbackDNS()
            return
        }
        
        print("\(self.domain): Received SRV records: \(String(describing: self.resolver.results))")
        self.handleSRVResults(results: self.convertSRVRecords(results: self.resolver.results))
    }
    
    @objc internal func resolverTimeout(timer: Timer) {
        if(self.resolver.isFinished) {
            return
        }
        
        print("\(self.domain): Resolver timed out")
        
        self.resolver.stop()
        self.handleSRVResults(results: self.convertSRVRecords(results: self.resolver.results))
    }
}

protocol XMPPStanzaObserver {
    func stanzaReceived(element: Element)
}

struct XMPPConnectionStatus {
    var serviceAvailable: Bool
    var secure: Bool
    var canLogin: Bool
    var canRegister: Bool
}

protocol XMPPConnectionObserver {
    func xmppCannotConnect(error: Error)
    func xmppConnected(connectionStatus: XMPPConnectionStatus)
}
