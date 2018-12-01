//
//  AddDomainTableViewController.swift
//  xmppclient
//
//  Created by Michael Johnson on 11/22/18.
//  Copyright © 2018 Michael Johnson. All rights reserved.
//

import UIKit

import libxmpp

class AddDomainTableViewController: UITableViewController, XMPPConnectionDelegate {

    @IBOutlet weak var domainField: UITextField!
    @IBOutlet var cancelButton: UIBarButtonItem!
    @IBOutlet var nextButton: UIBarButtonItem!

    var activityIndicator: UIActivityIndicatorView = UIActivityIndicatorView(style: .gray)

    var xmppConnection: XMPPConnection!

    override func viewDidLoad() {
        super.viewDidLoad()

        //self.navigationItem.setHidesBackButton(true, animated: false)

        //self.domainField.becomeFirstResponder()
    }

    override func viewWillDisappear(_ animated: Bool) {
        if self.xmppConnection != nil {
            self.xmppConnection.disconnect()
            self.xmppConnection = nil
        }
    }

    internal func testDomain() {
        self.beginVerifying()

        self.xmppConnection = XMPPConnection(forDomain: self.domainField.text!, allowInsecure: false)
        self.xmppConnection.connectionDelegate = self
        DispatchQueue.global(qos: .userInitiated).async {
            self.xmppConnection.connect()
        }
    }

    internal func beginVerifying() {
        self.domainField.resignFirstResponder()

        self.domainField.isEnabled = false

        self.navigationItem.leftBarButtonItem = nil
        self.navigationItem.rightBarButtonItem = nil

        self.navigationItem.titleView = self.activityIndicator
        self.activityIndicator.isHidden = false
        self.activityIndicator.startAnimating()
    }

    internal func endVerifying() {
        self.domainField.isEnabled = true

        self.navigationItem.leftBarButtonItem = self.cancelButton
        self.navigationItem.rightBarButtonItem = self.nextButton

        self.activityIndicator.stopAnimating()
        self.activityIndicator.isHidden = true
        self.navigationItem.titleView = nil
    }

    internal func askUserInsecure() {
        #warning("Asking the user about an insecure domain still needs to be completed")
        let alert = UIAlertController(title: nil, message: "Server is insecure", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Default action"), style: .default, handler: nil))
        self.present(alert, animated: true, completion: nil)
    }

    func xmppCannotConnect(error: Error) {
        DispatchQueue.main.sync {
            self.endVerifying()

            var userText: String = ""
            switch error {
            case is XMPPNoSuchDomainError:
                userText = "The given domain does not exist."
            case is XMPPUnableToConnectError:
                userText = "The domain did not respond to connection attempts."
            case is XMPPServiceNotSupportedError:
                userText = "The given domain does not support Jabber."
            case is XMPPIncompatibleError:
                userText = "The given domain requires features that this client doesn't support."
            case is XMPPCriticalSSLError:
                return self.askUserInsecure()
            default:
                userText = "An unknown error occured while connecting to the domain."
            }

            let alert = UIAlertController(title: nil, message: userText, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Default action"), style: .default, handler: nil))
            self.present(alert, animated: true, completion: nil)

            self.xmppConnection = nil
        }
    }

    func xmppConnected(connectionStatus: XMPPConnectionStatus) {
        DispatchQueue.main.sync {
            self.endVerifying()

            print("connection status:", connectionStatus)

            let alert = UIAlertController(title: nil, message: "Sucessfully connected", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Default action"), style: .default, handler: nil))
            self.present(alert, animated: true, completion: nil)
        }
    }

    @IBAction func domainValueChanged(_ sender: UITextField) {
        let canContinue = ((self.domainField.text?.count ?? 0) > 0)

        self.nextButton.isEnabled = canContinue
    }

    @IBAction func goButtonPressed(_ sender: Any) {
        self.testDomain()
    }

    @IBAction func cancelButtonPressed(_ sender: UIBarButtonItem) {
        self.dismiss(animated: true, completion: nil)
    }

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

}
