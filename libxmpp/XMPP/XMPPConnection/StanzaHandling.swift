//
//  StanzaHandling.swift
//  xmppclient
//
//  Created by Michael Johnson on 11/23/18.
//  Copyright © 2018 Michael Johnson. All rights reserved.
//

import Foundation

extension XMPPConnection {
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
}
