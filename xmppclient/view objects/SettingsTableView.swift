//
//  ResizingTableView.swift
//  xmppclient
//
//  Created by Michael Johnson on 11/21/18.
//  Copyright © 2018 Michael Johnson. All rights reserved.
//

import UIKit
import CoreData

class SettingsTableView: UITableView, UITableViewDataSource, UITableViewDelegate, NSFetchedResultsControllerDelegate {
    override var contentSize: CGSize {
        didSet {
            self.invalidateIntrinsicContentSize()
        }
    }

    override var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.noIntrinsicMetric, height: self.contentSize.height)
    }

    var serverFetchedResultsController: NSFetchedResultsController<Server>!

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)

        self.delegate = self
        self.dataSource = self

        self.initializeFetchedResultsController()
    }

    override init(frame: CGRect, style: UITableView.Style) {
        super.init(frame: frame, style: style)
        fatalError("Unexpectedly using frame-type init")
    }

    func initializeFetchedResultsController() {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
            fatalError("Application delegate was not of AppDelegate class")
        }
        let moc = appDelegate.persistentContainer.viewContext

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

    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if(indexPath.section == 0) {
            let lastRow = (tableView.numberOfRows(inSection: indexPath.section) - 1)
            if(indexPath.row != lastRow) {
                let cell = tableView.dequeueReusableCell(withIdentifier: "showAccount", for: indexPath)

                guard let object = self.serverFetchedResultsController?.object(at: indexPath) else {
                    fatalError("Attempt to configure cell without a managed object")
                }

                cell.textLabel?.text = object.domain

                return cell
            } else {
                return tableView.dequeueReusableCell(withIdentifier: "addAccount", for: indexPath)
            }
        }

        fatalError("Got request for cell in unknown section: \(indexPath.section)")
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if(section == 0) {
            guard let sections = serverFetchedResultsController.sections else {
                return 1
            }

            let section = sections[0]
            let rows = section.numberOfObjects
            return rows + 1
        }

        fatalError("Got request for number of rows in unknown section: \(section)")
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0:
            return "Accounts"
        default:
            fatalError("Got request for section title in unknown section: \(section)")
        }
    }

    func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        self.beginUpdates()
    }

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange sectionInfo: NSFetchedResultsSectionInfo, atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType) {
        var actualSectionIndex: Int
        if(controller == self.serverFetchedResultsController) {
            actualSectionIndex = 0
        } else {
            fatalError("Got section change notice from unknown controller")
        }
        switch type {
        case .insert:
            self.insertSections(IndexSet(integer: actualSectionIndex), with: .fade)
        case .delete:
            self.deleteSections(IndexSet(integer: actualSectionIndex), with: .fade)
        case .move:
            break
        case .update:
            break
        }
    }

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        var actualSection: Int
        if(controller == self.serverFetchedResultsController) {
            actualSection = 0
        } else {
            fatalError("Got section change notice from unknown controller")
        }

        var correctedIndexPath: IndexPath?
        var correctedNewIndexPath: IndexPath?

        if(indexPath != nil) {
            let iP = indexPath!
            correctedIndexPath = IndexPath(row: iP.row, section: actualSection)
            correctedIndexPath?.item = iP.item
        }

        if(newIndexPath != nil) {
            let iP = newIndexPath!
            correctedNewIndexPath = IndexPath(row: iP.row, section: actualSection)
            correctedNewIndexPath?.item = iP.item
        }

        switch type {
        case .insert:
            self.insertRows(at: [correctedNewIndexPath!], with: .fade)
        case .delete:
            self.deleteRows(at: [correctedIndexPath!], with: .fade)
        case .update:
            self.reloadRows(at: [correctedIndexPath!], with: .fade)
        case .move:
            self.moveRow(at: correctedIndexPath!, to: correctedNewIndexPath!)
        }
    }

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        self.endUpdates()
    }
}
