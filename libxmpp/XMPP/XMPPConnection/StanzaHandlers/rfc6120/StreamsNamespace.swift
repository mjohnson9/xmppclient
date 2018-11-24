//
//  StreamsNamespace.swift
//  xmppclient
//
//  Created by Michael Johnson on 11/23/18.
//  Copyright © 2018 Michael Johnson. All rights reserved.
//

import Foundation
import os.log

extension XMPPConnection {
    // MARK: Handler functions
    
    internal func processStreamsNamespace(stanza: Element) {
        switch(stanza.tag) {
        case "features":
            return self.processFeatures(stanza: stanza)
        case "error":
            return self.receivedStreamError(stanza: stanza)
        default:
            os_log(.info, log: XMPPConnection.osLog, "%s: Unable to handle stanza with tag %{public}s in namespace %{public}s", self.domain, stanza.tag, stanza.resolvedNamespace)
            self.sendStreamErrorAndClose(tag: "unsupported-stanza-type")
            return
        }
    }
    
    internal func receivedStreamStart(stanza: Element) {
        if let defaultNamespace = stanza.defaultNamespace {
            guard defaultNamespace == "jabber:client" else {
                os_log(.info, log: XMPPConnection.osLog, "%s: Received invalid content namespace: %{public}s", self.domain, stanza.defaultNamespace)
                self.sendStreamErrorAndClose(tag: "invalid-namespace")
                return
            }
        }
        
        guard let versionAttribute = stanza.attributes["version"] else {
            // Version is a required attribute
            os_log(.info, log: XMPPConnection.osLog, "%s: Stream start is missing version attribute", self.domain)
            self.sendStreamErrorAndClose(tag: "invalid-xml")
            return
        }
        
        guard let version = self.getVersion(versionAttribute) else {
            os_log(.info, log: XMPPConnection.osLog, "%s: Unable to parse version attribute: %{public}s", self.domain, versionAttribute)
            self.sendStreamErrorAndClose(tag: "invalid-xml")
            return
        }
        
        if(version.major != 1 || version.minor != 0) {
            os_log(.info, log: XMPPConnection.osLog, "%s: Server version is unsupported: %{public}d.%{public}d", self.domain, version.major, version.minor)
            self.sendStreamErrorAndClose(tag: "unsupported-version")
            return
        }
        
        os_log(.info, log: XMPPConnection.osLog, "%s: Received start of stream", self.domain)
    }
    
    internal func receivedStreamEnd() {
        os_log(.info, log: XMPPConnection.osLog, "%s: Received end of stream", self.domain)
        
        if(!self.session.requestsMade.endStream) {
            self.writeStreamEnd()
            self.disconnectWithoutRetry()
            return
        }
        
        self.disconnectAndRetry()
    }
    
    // MARK: Functions for other modules
    internal func sendStreamOpener() {
        self.writeStreamBegin(xmppVersion: "1.0", to: self.domain, from: nil)
    }
    
    // MARK: Helper functions
    
    private func getVersion(_ version: String) -> (major: Int, minor: Int)? {
        let splitVersion = version.components(separatedBy: ".")
        if(splitVersion.count != 2) {
            return nil
        }
        
        guard let major = Int(splitVersion[0]) else {
            return nil
        }
        
        guard let minor = Int(splitVersion[1]) else {
            return nil
        }
        
        return (major: major, minor: minor)
    }
}
