//
//  StreamsNamespace.swift
//  xmppclient
//
//  Created by Michael Johnson on 11/23/18.
//  Copyright © 2018 Michael Johnson. All rights reserved.
//

import Foundation

extension XMPPConnection {
    // MARK: Handler functions
    
    internal func processStreamsNamespace(stanza: Element) {
        switch(stanza.tag) {
        case "features":
            return self.processFeatures(stanza: stanza)
        case "error":
            return self.receivedStreamError(stanza: stanza)
        default:
            print("\(self.domain): Unable to handle stanza with tag", stanza.tag, "in namespace", stanza.resolvedNamespace)
            self.sendStreamErrorAndClose(tag: "unsupported-stanza-type")
            return
        }
    }
    
    internal func receivedStreamStart(stanza: Element) {
        guard let versionAttribute = stanza.attributes["version"] else {
            // Version is a required attribute
            print("\(self.domain) Stream start is missing version attribute")
            self.sendStreamErrorAndClose(tag: "invalid-xml")
            return
        }
        
        guard let version = self.getVersion(versionAttribute) else {
            print("\(self.domain) Unable to parse version attribute: \(versionAttribute)")
            self.sendStreamErrorAndClose(tag: "invalid-xml")
            return
        }
        
        if(version.major != 1 || version.minor != 0) {
            print("\(self.domain) Server version is unsupported: \(version.major).\(version.minor)")
            self.sendStreamErrorAndClose(tag: "unsupported-version")
            return
        }
        
        print("\(self.domain): Received start of stream")
    }
    
    internal func receivedStreamEnd() {
        print("\(self.domain): Received end of stream")
        
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
