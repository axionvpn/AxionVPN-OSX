//
//  AxionNetworkView.h
//  AxionVPN
//
//  Created by User Name on 10/8/15.
//  Copyright © 2015 User Name. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface AxionNetworkView : NSView <NSWindowDelegate,NSComboBoxDelegate,NSComboBoxDataSource> {
    IBOutlet NSComboBox *VPNList;
    IBOutlet NSButton *connectButton;
    IBOutlet NSTextField *BadCredsMsg;
    IBOutlet NSTextField *usernameField;
    IBOutlet NSSecureTextField *passwordField;
    IBOutlet NSTextField *versionField;
    IBOutlet NSButton * saveCredsInKeychainCheckbox;

    NSArray *sites;
    
}

-(IBAction) connectButtonPressed:(id)sender;


-(IBAction) getAxionAcccount: (id) sender;
-(IBAction) forgotPassWord: (id) sender;



-(BOOL)     isSaveCredsInKeychainChecked;


@end
