//
//  Stream.swift
//  xmppclient
//
//  Created by Michael Johnson on 11/23/18.
//  Copyright © 2018 Michael Johnson. All rights reserved.
//

import Foundation
import os.log

private struct AssociatedKeys {
    static var attemptReconnect: UInt8 = 0
    static var currentConnectionAddress: UInt8 = 0
    static var inStream: UInt8 = 0
    static var outStream: UInt8 = 0
    static var readThread: UInt8 = 0
    static var connectionErrors: UInt8 = 0
    static var gracefulCloseTimer: UInt8 = 0
}

extension XMPPConnection: StreamDelegate {
    // MARK: Variables
    private var attemptReconnect: Bool {
        get {
            guard let value = objc_getAssociatedObject(self, &AssociatedKeys.attemptReconnect) as? Bool else {
                return true
            }
            return value
        }
        set(newValue) {
            objc_setAssociatedObject(self, &AssociatedKeys.attemptReconnect, newValue, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    internal private(set) var currentConnectionAddress: Int {
        get {
            guard let value = objc_getAssociatedObject(self, &AssociatedKeys.currentConnectionAddress) as? Int else {
                return 0
            }
            return value
        }
        set(newValue) {
            objc_setAssociatedObject(self, &AssociatedKeys.currentConnectionAddress, newValue, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    private var inStream: InputStream! {
        get {
            guard let value = objc_getAssociatedObject(self, &AssociatedKeys.inStream) as? InputStream else {
                return nil
            }
            return value
        }
        set(newValue) {
            objc_setAssociatedObject(self, &AssociatedKeys.inStream, newValue, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    private var outStream: OutputStream! {
        get {
            guard let value = objc_getAssociatedObject(self, &AssociatedKeys.outStream) as? OutputStream else {
                return nil
            }
            return value
        }
        set(newValue) {
            objc_setAssociatedObject(self, &AssociatedKeys.outStream, newValue, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    private var readThread: Thread! {
        get {
            guard let value = objc_getAssociatedObject(self, &AssociatedKeys.readThread) as? Thread else {
                return nil
            }
            return value
        }
        set(newValue) {
            objc_setAssociatedObject(self, &AssociatedKeys.readThread, newValue, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    private var gracefulCloseTimer: Timer! {
        get {
            guard let value = objc_getAssociatedObject(self, &AssociatedKeys.gracefulCloseTimer) as? Timer else {
                return nil
            }
            return value
        }
        set(newValue) {
            objc_setAssociatedObject(self, &AssociatedKeys.gracefulCloseTimer, newValue, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    private var connectionErrors: [Error]! {
        get {
            guard let value = objc_getAssociatedObject(self, &AssociatedKeys.connectionErrors) as? [Error] else {
                return nil
            }
            return value
        }
        set(newValue) {
            objc_setAssociatedObject(self, &AssociatedKeys.connectionErrors, newValue, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    internal var streamIsOpen: Bool {
        get {
            if self.inStream == nil || self.outStream == nil {
                return false
            }
            
            return true
        }
    }
    
    // MARK: Connection functions
    
    internal func startConnectionAttempts() {
        self.readThread = Thread(target: self, selector: #selector(self.readThreadMain), object: nil)
        self.readThread.name = "XMPP receiving: \(self.domain)"
        self.readThread.start()
    }
    
    @objc private func readThreadMain() {
        if(self.connectionAddresses == nil) {
            self.dispatchCannotConnect(error: XMPPUnableToConnectError())
            return
        }
        
        self.connectionErrors = []
        self.connectionErrors.reserveCapacity(self.connectionAddresses.count)
        
        while(self.attemptReconnect) {
            if(self.currentConnectionAddress > (self.connectionAddresses.count - 1)) {
                print("\(self.domain): Ran out of hosts to connect to")
                self.dispatchCannotConnect(error: XMPPUnableToConnectError())
                return
            }
            
            let connectionAddress = self.connectionAddresses[self.currentConnectionAddress]
            self.currentConnectionAddress += 1
            
            let error = self.attemptConnection(toHostname: connectionAddress.host, toPort: connectionAddress.port)
            
            // Send some debug information
            if let nsError = error as NSError? {
                print("\(self.domain): Disconnected from \(connectionAddress.host):\(connectionAddress.port) with error: (\(nsError.domain):\(nsError.code)) \(nsError.localizedDescription) | \(nsError.localizedFailureReason ?? "(no localized failure reason)")")
            } else if(error != nil) {
                print("\(self.domain): Disconnected from \(connectionAddress.host):\(connectionAddress.port) with error: (\(String(describing: error))")
            } else {
                print("\(self.domain): Disconnected from \(connectionAddress.host):\(connectionAddress.port)")
            }
        }
    }
    
    private func attemptConnection(toHostname hostname: String, toPort port: UInt16) -> Error? {
        print("\(self.domain): Attempting connection to \(hostname):\(port)")
        
        self.session = XMPPSession()
        
        var inStream: InputStream!
        var outStream: OutputStream!
        
        Stream.getStreamsToHost(withName: hostname, port: Int(port), inputStream: &inStream, outputStream: &outStream)
        
        self.inStream = inStream
        self.outStream = outStream
        
        self.inStream.delegate = self
        self.outStream.delegate = self
        
        DispatchQueue.global(qos: .background).async {
            self.outStream.schedule(in: RunLoop.current, forMode: .common)
        }
        
        self.inStream.setProperty(kCFBooleanTrue, forKey: kCFStreamPropertySocketExtendedBackgroundIdleMode as Stream.PropertyKey)
        self.outStream.setProperty(kCFBooleanTrue, forKey: kCFStreamPropertySocketExtendedBackgroundIdleMode as Stream.PropertyKey)
        
        self.outStream.open()
        
        
        var parser = self.createParser()
        var success: Bool = true
        while(success && self.inStream != nil) {
            success = parser.parse()
            
            if(self.parserNeedsReset && self.inStream != nil) {
                parser = self.createParser()
                success = true // Ignore any failures that came from resetting the parser
                self.parserHasReset()
            }
        }
        
        /*if !success {
            print("\(self.domain): Parser failed with an error")
            if self.outStream != nil && self.outStream.hasSpaceAvailable {
                self.sendStreamErrorAndClose(tag: "bad-format")
            }
            self.disconnectAndRetry()
            return XMPPXMLError()
        }*/
        
        var error: Error? = nil
        if(self.inStream != nil) {
            error = self.inStream.streamError
        }
        
        inStream.close()
        outStream.close()
        
        return error
    }
    
    // MARK: Functions exposed to other modules
    internal func resetConnectionAttempts() {
        self.currentConnectionAddress = 0
    }
    
    // MARK: Stream delegate functions
    public func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
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
            break
        case Stream.Event.endEncountered:
            print("\(self.domain): \(aStream) encountered EOF")
            break
        case Stream.Event.errorOccurred:
            print("\(self.domain): \(aStream) had an error: \(String(describing: aStream.streamError))")
            break
        default:
            print("\(self.domain): Received unhandled event: \(eventCode)")
            break
        }
    }
    
    // MARK: Functions for other extensions
    internal func streamEnableTLS() {
        let sslSettings: Dictionary<NSString, Any> = [
            NSString(format: kCFStreamSSLLevel): kCFStreamSocketSecurityLevelNegotiatedSSL,
            NSString(format: kCFStreamSSLPeerName): NSString(string: self.domain)
        ]
        
        self.outStream.setProperty(sslSettings, forKey: kCFStreamPropertySSLSettings as Stream.PropertyKey)
        self.inStream.setProperty(sslSettings, forKey: kCFStreamPropertySSLSettings as Stream.PropertyKey)
    }
    
    // MARK: Write functions
    
    internal func write(_ element: Element) {
        self.write(string: element.serialize())
    }
    
    internal func writeStreamBegin(xmppVersion: String, to: String, from: String?) {
        let openStream: NSMutableString = "<?xml version='1.0' encoding='UTF-8'?><stream:stream"
        if from != nil {
            openStream.append(" from='\(Element.escapeAttribute(from!))'")
        }
        openStream.append(" to='\(Element.escapeAttribute(to))'")
        openStream.append(" version='\(Element.escapeAttribute(xmppVersion))'")
        openStream.append(" xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams'>")
        
        self.write(string: openStream as String)
        
        print("\(self.domain): Sent stream opening")
    }
    
    internal func sendStreamErrorAndClose(tag: String) {
        let streamError  = self.constructStreamError(tag: tag)
        self.write(streamError)
        print("\(self.domain): Sent stream error:", tag)
        self.disconnectAndRetry()
    }
    
    internal func writeStreamEnd() {
        self.write(string: "</stream:stream>")
    }
    
    private func write(string: String) {
        let encodedString: Data = string.data(using: .utf8)!
        _ = encodedString.withUnsafeBytes {
            self.outStream.write($0, maxLength: encodedString.count)
        }
        os_log(.debug, log: XMPPConnection.osLog, "%s <- %{private}s", self.domain, string)
    }
    
    // MARK: Disconnect functions

    public func disconnect() {
        self.disconnectGracefully()
    }
    
    internal func disconnectGracefully() {
        self.session!.requestsMade.endStream = true
        self.writeStreamEnd()
        
        self.gracefulCloseTimer = Timer(timeInterval: 1.0, target: self, selector: #selector(self.gracefulCloseTimeout), userInfo: nil, repeats: false)
        DispatchQueue.global(qos: .background).async {
            RunLoop.current.add(self.gracefulCloseTimer, forMode: RunLoop.Mode.common)
        }
    }
    
    internal func disconnectWithoutRetry() {
        self.attemptReconnect = false
        self.disconnectAndRetry()
    }
    
    internal func disconnectAndRetry() {
        self.session = nil
        
        if self.inStream != nil {
            self.inStream.close()
            self.inStream = nil
        }
        
        if self.outStream != nil {
            self.outStream.close()
            self.outStream = nil
        }
        
        if self.gracefulCloseTimer != nil {
            DispatchQueue.global(qos: .background).async {
                self.gracefulCloseTimer.invalidate()
                self.gracefulCloseTimer = nil
                
                print("Invalidated graceful close timer")
            }
        }
    }
    
    // MARK: Graceful close timeout
    
    @objc private func gracefulCloseTimeout() {
        self.disconnectWithoutRetry()
        print("\(self.domain): Graceful close timed out")
    }
    
    // MARK: Helper functions
    
    private func createParser() -> XMLParser {
        let parser = XMLParser(stream: self.inStream)
        
        parser.shouldResolveExternalEntities = false
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = true
        parser.externalEntityResolvingPolicy = .never
        
        parser.delegate = self
        
        return parser
    }
    
    private func constructStreamError(tag: String) -> Element {
        let root = Element()
        root.prefix = "stream"
        root.tag = "error"
        root.attributes["to"] = self.domain
        
        let child = Element()
        child.tag = tag
        child.defaultNamespace = "urn:ietf:params:xml:ns:xmpp-streams"
        
        root.children = [child]
        
        return root
    }
}
