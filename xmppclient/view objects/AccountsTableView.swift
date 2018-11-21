//
//  ResizingTableView.swift
//  xmppclient
//
//  Created by Michael Johnson on 11/21/18.
//  Copyright © 2018 Michael Johnson. All rights reserved.
//

import UIKit

class AccountsTableView: UITableView, UITableViewDataSource, UITableViewDelegate {
    override var contentSize:CGSize {
        didSet {
            self.invalidateIntrinsicContentSize()
        }
    }
    
    override var intrinsicContentSize: CGSize {
        self.layoutIfNeeded()
        var height = self.contentSize.height
        let minHeight = self.rowHeight + 12
        if(height < minHeight) {
            height = minHeight
        }
        print("New table height:", height)
        return CGSize(width: UIViewNoIntrinsicMetric, height: height)
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        // #warning Incomplete implementation, return the number of sections
        return 2
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        return tableView.dequeueReusableCell(withIdentifier: "addAccount", for: indexPath)
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch(section) {
        case 0:
            // #warning Incomplete, return actual number of rows
            return 0
        case 1:
            return 1
        default:
            return 0
        }
    }
    
    override func willMove(toSuperview newSuperview: UIView?) {
        self.delegate = self
        self.dataSource = self
    }
}
