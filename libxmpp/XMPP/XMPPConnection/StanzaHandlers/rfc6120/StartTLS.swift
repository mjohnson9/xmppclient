//
//  TLS.swift
//  xmppclient
//
//  Created by Michael Johnson on 11/23/18.
//  Copyright © 2018 Michael Johnson. All rights reserved.
//

import Foundation
import os.log

extension XMPPConnection {
    internal func processTlsNamespace(stanza: Element) {
        switch stanza.tag {
        case "proceed":
            if !self.session!.requestsMade.startTls {
                os_log(.info, log: XMPPConnection.osLog, "%s: Server sent StartTLS proceed without being asked", self.domain)
                self.sendStreamErrorAndClose(tag: "invalid-xml")
                return
            }

            self.enableTLS()
            return
        case "failure":
            if !self.session!.requestsMade.startTls {
                os_log(.info, log: XMPPConnection.osLog, "%s: Server sent StartTLS failure without being asked", self.domain)
                self.sendStreamErrorAndClose(tag: "invalid-xml")
                return
            }

            self.disconnectAndRetry()
            return
        default:
            os_log(.info, log: XMPPConnection.osLog, "%s: Unable to handle stanza with tag %{public}s in namespace %{public}s", self.domain, stanza.tag, stanza.resolvedNamespace)
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

        os_log(.info, log: XMPPConnection.osLog, "%s: Enabled TLS", self.domain)

        self.resetParser()
        self.session = XMPPSession()
        self.session!.secure = true
        self.sendStreamOpener()
    }
}
