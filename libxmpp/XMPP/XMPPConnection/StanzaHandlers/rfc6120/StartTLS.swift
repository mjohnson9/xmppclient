//
//  TLS.swift
//  xmppclient
//
//  Created by Michael Johnson on 11/23/18.
//  Copyright © 2018 Michael Johnson. All rights reserved.
//

import Foundation

extension XMPPConnection {
    internal func processTlsNamespace(stanza: Element) {
        switch(stanza.tag) {
        case "proceed":
            if(!self.session!.requestsMade.startTls) {
                print("\(self.domain): Server sent StartTLS proceed without being asked")
                self.sendStreamErrorAndClose(tag: "invalid-xml")
                return
            }
            
            self.enableTLS()
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
    
    internal func negotiateTLS() {
        let element = Element()
        element.tag = "starttls"
        element.defaultNamespace = "urn:ietf:params:xml:ns:xmpp-tls"
        
        self.session!.requestsMade.startTls = true
        self.write(element)
    }
    
    internal func enableTLS() {
        self.streamEnableTLS()
        
        print("\(self.domain): Enabled TLS")
        
        self.resetParser()
        self.session = XMPPSession()
        self.session!.secure = true
        self.sendStreamOpener()
    }
}
