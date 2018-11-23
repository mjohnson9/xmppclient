//
//  ContactTableViewCell.swift
//  xmppclient
//
//  Created by Michael Johnson on 11/20/18.
//  Copyright © 2018 Michael Johnson. All rights reserved.
//

import UIKit

class ContactTableViewCell: UITableViewCell {
    @IBOutlet weak var avatar: UIImageView!
    @IBOutlet weak var name: UILabel!
    @IBOutlet weak var lastMessage: UILabel!
    @IBOutlet weak var lastMessageTime: UILabel!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        
        self.avatar.layer.cornerRadius = self.avatar.frame.size.height / 2
        self.avatar.layer.masksToBounds = true
        self.avatar.layer.borderWidth = 0
        // Initialization code
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }

}
