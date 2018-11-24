//
//  StanzaHandling.swift
//  xmppclient
//
//  Created by Michael Johnson on 11/23/18.
//  Copyright © 2018 Michael Johnson. All rights reserved.
//

import Foundation
import os.log

extension XMPPConnection {
    internal func receivedStanza(stanza: Element) {
        os_log(.debug, log: XMPPConnection.osLog, "%s <- %{private}s", self.domain, stanza.serialize())
        
        switch(stanza.resolvedNamespace) {
        case "http://etherx.jabber.org/streams":
            return self.processStreamsNamespace(stanza: stanza)
        case "urn:ietf:params:xml:ns:xmpp-tls":
            return self.processTlsNamespace(stanza: stanza)
        default:
            os_log(.info, log: XMPPConnection.osLog, "%s: Unable to handle stanza from namespace %{public}s", self.domain, stanza.resolvedNamespace)
            self.sendStreamErrorAndClose(tag: "unsupported-stanza-type")
            return
        }
    }
}
