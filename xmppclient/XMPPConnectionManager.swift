//
//  XMPPConnectionManager.swift
//  xmppclient
//
//  Created by Michael Johnson on 11/22/18.
//  Copyright © 2018 Michael Johnson. All rights reserved.
//

import CoreData
import Foundation

class XMPPConnectionManager: NSObject, NSFetchedResultsControllerDelegate {
    var appDelegate: AppDelegate
    var xmppConnections: [XMPPConnection?] = []

    var serverFetchedResultsController: NSFetchedResultsController<Server>!
    
    init(withAppDelegate parent: AppDelegate) {
        self.appDelegate = parent

        super.init()

        self.initializeFetchedResultsController()
    }
    
    func initializeFetchedResultsController() {
        let moc = self.appDelegate.persistentContainer.viewContext
        
        let request = NSFetchRequest<Server>(entityName: "Server")
        let domainSort = NSSortDescriptor(key: "domain", ascending: true)
        request.sortDescriptors = [domainSort]
        
        self.serverFetchedResultsController = NSFetchedResultsController<Server>(fetchRequest: request, managedObjectContext: moc, sectionNameKeyPath: nil, cacheName: nil)
        self.serverFetchedResultsController.delegate = self
        
        do {
            try self.serverFetchedResultsController.performFetch()
        } catch {
            fatalError("Failed to initialize FetchedResultsController: \(error)")
        }
    }
    
    internal func startNewConnection(indexPath: IndexPath) {
        guard let data = self.serverFetchedResultsController?.object(at: indexPath) else {
            fatalError("Attempt to start connection for a path without an object")
        }
        
        if(self.xmppConnections.count < (indexPath.row + 1)) {
            let needToAdd = (indexPath.row + 1) - self.xmppConnections.count
            for _ in 1...needToAdd {
                self.xmppConnections.append(nil)
            }
        }
        
        
        let connection = XMPPConnection(forDomain: data.domain!)
        self.xmppConnections[indexPath.row] = connection
        DispatchQueue.global(qos: .background).async {
            connection.connect()
        }
    }
    
    internal func stopConnection(indexPath: IndexPath) {
        
    }
    
    internal func moveConnection(oldIndexPath: IndexPath, newIndexPath: IndexPath) {
        
    }
    
    internal func updateConnection(indexPath: IndexPath) {
        
    }
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        if(controller == self.serverFetchedResultsController) {
            switch type {
            case .insert:
                self.startNewConnection(indexPath: indexPath!)
            case .delete:
                self.stopConnection(indexPath: indexPath!)
            case .move:
                self.moveConnection(oldIndexPath: indexPath!, newIndexPath: newIndexPath!)
            case .update:
                self.updateConnection(indexPath: indexPath!)
            }
        } else {
            fatalError("Got section change notice from unknown controller")
        }
    }
}
