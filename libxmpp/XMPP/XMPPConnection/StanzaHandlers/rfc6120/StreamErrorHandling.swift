//
//  StreamErrorHandling.swift
//  xmppclient
//
//  Created by Michael Johnson on 11/23/18.
//  Copyright © 2018 Michael Johnson. All rights reserved.
//

import Foundation
import os.log

extension XMPPConnection {
    internal func receivedStreamError(stanza: Element) {
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
        
        let attemptedConnectionAddress = self.connectionAddresses![self.currentConnectionAddress]
        os_log(.info, log: XMPPConnection.osLog, "%s: Received %{public}s error from %s:%d", self.domain, attemptedConnectionAddress.host, attemptedConnectionAddress.port)
        
        switch(errorTag) {
        case "see-other-host":
            self.receivedSeeOtherHost(stanza: stanza, errorContents: errorContents)
            return
        default:
            // Switch has to be exhaustive
            self.disconnectAndRetry()
            return
        }
    }
    
    // MARK: Private error handlers
    private func receivedSeeOtherHost(stanza: Element, errorContents: String?) {
        guard errorContents != nil else {
            os_log(.info, log: XMPPConnection.osLog, "%s: Received see-other-host error with no host specified", self.domain)
            self.disconnectAndRetry()
            return
        }
        
        let newHost = errorContents!
        os_log(.info, log: XMPPConnection.osLog, "%s: Got referral to another host: %s", self.domain, newHost)
        
        var host = newHost
        var port: UInt16 = 5222
        if let portIndex = newHost.lastIndex(of: ":") {
            let afterColonIndex = String.Index(encodedOffset: portIndex.encodedOffset + 1)
            let portStr = newHost.suffix(from: afterColonIndex)
            if let portNum = UInt16(portStr) { // Parsing will fail if this is the end of an IPv6 address. That's deliberate.
                port = portNum
                host = String(newHost.prefix(upTo: portIndex))
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
    }
}
