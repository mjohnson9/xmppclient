//
//  FeatureNegotiation.swift
//  xmppclient
//
//  Created by Michael Johnson on 11/23/18.
//  Copyright © 2018 Michael Johnson. All rights reserved.
//

import Foundation
import os.log

extension XMPPConnection {
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
                        os_log(.info, log: XMPPConnection.osLog, "%s: Received TLS offer inside of a secure session", self.domain)
                    }
                }
                break
            default:
                if(!anyRequired && feature.required) {
                    anyRequired = true
                }
                break
            }
        }
        
        if(anyRequired && nextNegotiable == nil) {
            os_log(.info, log: XMPPConnection.osLog, "%s: We don't support any of the required features. Disconnecting.", self.domain)
            self.sendStreamErrorAndClose(tag: "unsupported-feature")
            return self.fatalConnectionError(XMPPIncompatibleError())
        }
        
        if(nextNegotiable != nil) {
            if(nextNegotiable.resolvedNamespace == "urn:ietf:params:xml:ns:xmpp-tls" && nextNegotiable.tag == "starttls") {
                return self.negotiateTLS()
            } else {
                os_log(.error, log: XMPPConnection.osLog, "%s: Chose feature for negotiation that we don't support: %{public}s -> %{public}s", self.domain, nextNegotiable.resolvedNamespace, nextNegotiable.tag)
                fatalError()
            }
        } else {
            os_log(.info, log: XMPPConnection.osLog, "%s: Negotiation finished.", self.domain)
            self.resetConnectionAttempts() // Finishing negotiation represents a successful connection
            
            #warning("Currently disconnecting after feature negotiation -- remove this later")
            self.dispatchConnected(status: XMPPConnectionStatus(serviceAvailable: true, secure: self.session!.secure, canLogin: false, canRegister: false))
            self.disconnectGracefully()
        }
    }
    
    // MARK: Helper functions
    
    private func createFeature(_ stanza: Element) -> XMPPSession.Feature {
        var feature = XMPPSession.Feature(namespace: stanza.resolvedNamespace, name: stanza.tag, required: false, stanza: stanza)
        
        for child in stanza.children {
            if(child.tag == "required") {
                feature.required = true
            }
        }
        
        return feature
    }
}
