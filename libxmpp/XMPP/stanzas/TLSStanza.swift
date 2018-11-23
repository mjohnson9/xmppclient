//
//  TLSStanza.swift
//  xmppclient
//
//  Created by Michael Johnson on 11/23/18.
//  Copyright © 2018 Michael Johnson. All rights reserved.
//

import Foundation

/// This class is only used to differentiate values passed to TLS handling functions
class TLSStanza: Stanza {
    override init?(_ element: Element) {
        if(element.resolvedNamespace != "urn:ietf:params:xml:ns:xmpp-tls") {
            return nil
        }
        
        super.init(element)
    }
}
