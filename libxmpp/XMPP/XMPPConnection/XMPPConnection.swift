//
//  xmppconnection.swift
//  xmppclient
//
//  Created by Michael Johnson on 11/21/18.
//  Copyright © 2018 Michael Johnson. All rights reserved.
//

import Foundation
import Network
import os.log

class XMPPConnection : NSObject {
    static internal let osLog = OSLog(subsystem: "computer.johnson.libxmpp.XMPPConnection", category: "network")
    
    let domain: String
    
    // MARK: Shared variables
    internal var connectionAddresses: [(host: String, port: UInt16)]!
    internal private(set) var allowInsecure: Bool = false
    
    internal var session: XMPPSession!
    
    private var connectionObservers: [XMPPConnectionObserver] = []
    
    // MARK: Initialization and deinitialization
    
    init(forDomain domain: String, allowInsecure: Bool) {
        self.domain = domain
        self.allowInsecure = allowInsecure
    }
    
    deinit {
        objc_removeAssociatedObjects(self)
    }
    
    // MARK: Public interface
    
    public func connect() {
        os_log(.info, log: XMPPConnection.osLog, "%s: Connecting", self.domain)
        
        // Start by attempting to resolve SRV records
        self.resolveSRV()
    }
    
    public func addConnectionObserver(observer: XMPPConnectionObserver) -> Int {
        self.connectionObservers.append(observer)
        return self.connectionObservers.count - 1
    }
    
    public func removeConnectionObserver(observer: Int) {
        self.connectionObservers.remove(at: observer)
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
    
    internal func fatalConnectionError(_ error: Error) {
        self.disconnectWithoutRetry()
        self.dispatchCannotConnect(error: error)
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
