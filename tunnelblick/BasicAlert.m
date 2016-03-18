//
//  BasicAlert.m
//  AxionVPN
//
//  Created by User Name on 1/7/16.
//
//

#import "BasicAlert.h"

@interface BasicAlert ()

@end

@implementation BasicAlert


-(void) awakeFromNib {
    
    [[self window] setDelegate: self];
    

    
    NSWindow * w = [self window];
    
    [w center];
    [w display];
    [self showWindow: self];
    
    [NSApp activateIgnoringOtherApps: YES];
    
    [w makeKeyAndOrderFront: self];
}

- (void)windowDidLoad {
    [super windowDidLoad];
    
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
}


-(void)okButtonPressed:(id)sender
{
    NSLog(@"[okButtonPressed] Called");
    
}


-(void)upgradePressed:(id)sender
{
    NSLog(@"[upgradePressed] Called");
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString: @"http://axionvpn.com/vpn"]];    
    
}


@end
