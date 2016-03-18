//
//  AxionNetworkView.m
//  AxionVPN
//
//  Created by User Name on 10/8/15.
//  Copyright © 2015 User Name. All rights reserved.
//

#import "AxionNetworkView.h"
#import "AxionAPI.h"
#import "AuthAgent.h"
#import "ConfigurationManager.h"
#import "MenuController.h"


@implementation AxionNetworkView


extern NSString *memUserName;          //User name cached in memory only
extern NSString *memPassword;          //Password cached in memory only
BOOL bCloseWin;


-(NSString *)GetVersion
{
    NSDictionary * infoPlist = [[NSBundle mainBundle] infoDictionary];
    NSString * thisVersion = [infoPlist objectForKey: @"CFBundleShortVersionString"];
    NSString *verString = [NSString stringWithFormat:@"Version %@",thisVersion];
    return verString;
}


-(void)LoadCreds
{

    //Get valid creds for this
    AuthAgent * myAuthAgent = [[AuthAgent alloc] initWithConfigName: @"AxionVPN" credentialsGroup: @"AxionVPN"];
    
    [myAuthAgent setAuthMode: @"password"];
    
    
    //Validate creds, don't let continue until they are good
    
    
    NSArray *authArray = [myAuthAgent getUsernameAndPassword];
    
    if(authArray[0] != nil){
        usernameField.stringValue = authArray[0];
    }
    
    if(authArray[1] != nil){
        passwordField.stringValue = [authArray objectAtIndex:1];
    }
    
}


- (id)initWithCoder:(NSCoder*)coder
{
    
    NSLog(@"[AxionNetworkView:initWithCoder] Called");
    self = [super initWithCoder:coder];
    
    
    //Initialize the Array
    sites = nil;
   

    return self;
}


- (void) awakeFromNib{
    
    //setup code
    NSLog(@"[AxionNetworkView:awakeFromNib] Called");
    
    //Set the version string
    versionField.stringValue = [self GetVersion];
    
    //Load the creds
    [self LoadCreds];
    
    
    //Hide the error message
  //  NSColor *errColor =
   // [BadCredsMsg setTextColor:<#(NSColor * _Nullable)#>]
   // BadCredsMsg.stringValue = @"Invalid Username or Password";
    [BadCredsMsg setHidden:TRUE];
    
    //Load up the list of VPN's
    sites = [AxionAPI getVPNList];
    [VPNList reloadData];
    
    
}


- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    
    // Drawing code here.
    [[NSColor whiteColor] setFill];
    NSRectFill(dirtyRect);
    [super drawRect:dirtyRect];
    
}



- (NSString *)pathForTemporaryFileWithPrefix:(NSString *)prefix
{
    NSString *  result;
    
    result = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.ovpn", prefix]];
    assert(result != nil);
    
    
    return result;
}


#pragma - Window delegate functions


- (void)windowDidChangeOcclusionState:(NSNotification *)__unused notification
{
    
     NSLog(@"[AxionNetworkView:windowDidChangeOcclusionState] Called");
    if (self.window.occlusionState & NSWindowOcclusionStateVisible)
    {
        NSLog(@"[AxionNetworkView:windowDidChangeOcclusionState] Appearing");
        
        
        
        //First see if the network is available at all
        //by resolving the host name
        if( [((MenuController *)[NSApp delegate]) isNetworkAvailable] == FALSE){
        //if([MenuController isNetworkAvailable] == FALSE){
            NSLog(@"Can't Resolve Host");
            
            NSAlert *alert = [NSAlert alertWithMessageText:@"Could not connect to axionvpn.com"
                                             defaultButton:@"OK" alternateButton:nil otherButton:nil
                                 informativeTextWithFormat:@"Please make sure you're connected to the Internet"];
            
            
            [alert runModal];
            
            //Exit this screen
            NSWindow *w = [self window];
            [w close];
            
        }else{
            NSLog(@"Host successfully resolved");
        }

        //Set the version string
        versionField.stringValue = [self GetVersion];
        
        //Load the creds
        [self LoadCreds];
        
        
        //Hide the message
        [BadCredsMsg setHidden:TRUE];
        
        //Load up the list of VPN's
        sites = [AxionAPI getVPNList];
        [VPNList reloadData];    }
    else
    {
        NSLog(@"[AxionNetworkView:windowDidChangeOcclusionState] Dissappearing");

        // Disappear code here
        [BadCredsMsg setHidden:TRUE];
    }
}




#pragma URL Support functions


- (IBAction) getAxionAcccount:(id)sender
{
    NSLog(@"[getAxionAcccount] Called");
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString: @"http://axionvpn.com/"]];
    
}


- (IBAction) forgotPassWord:(id)sender
{
    NSLog(@"[forgotPassWord] Called");
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString: @"http://axionvpn.com/lostpw"]];
    
}


-(BOOL) isSaveCredsInKeychainChecked
{
    return (  [saveCredsInKeychainCheckbox state] == NSOnState  );
}


-(void) GetAndLoadConfig:(NSInteger) index
{

    NSLog(@"[AxionNetworkView:GetAndLoadConfig] Called with %ld",index);
   
    
    NSString *usernameLocal = nil;
    NSString *passwordLocal = nil;
    
    //Disable "Connect" button until we are done
    [connectButton setEnabled:FALSE];
    
    //First status
    [BadCredsMsg setTextColor:[NSColor blackColor]];
    BadCredsMsg.stringValue = @"Authenticating";
    [BadCredsMsg displayIfNeeded];
    [BadCredsMsg setHidden:FALSE];
    
    
    //Get valid creds for this
    AuthAgent * myAuthAgent = [[AuthAgent alloc] initWithConfigName: @"AxionVPN" credentialsGroup: @"AxionVPN"];
    
    [myAuthAgent setAuthMode: @"password"];
    
    
    //Validate creds
    usernameLocal = usernameField.stringValue;
    passwordLocal = passwordField.stringValue;
    
    NSLog(@"[AxionNetworkView:GetAndLoadConfig] Validating %@:%@",usernameLocal,passwordLocal);
    
    
    //Wait on a semaphore
    // dispatch_semaphore_wait(sema,DISPATCH_TIME_FOREVER);
    
    if( [AxionAPI ValidateCreds:usernameLocal andPass:passwordLocal] == FALSE){
        [BadCredsMsg setTextColor:[NSColor redColor]];
        BadCredsMsg.stringValue = @"Invalid Username or Password";
        
        //enable connect button
        [connectButton setEnabled:TRUE];

        return;
    }else{
        //Change our status to Downloading Configuration
        BadCredsMsg.stringValue = @"Downloading Configuration";
        
    }
    
    
    //Obtain the id for the VPN
    NSDictionary *VPNSite = [sites objectAtIndex:index];
    NSString *VPNid = [VPNSite objectForKey:@"id"];
    NSString *geoArea = [VPNSite objectForKeyedSubscript:@"geo_area"];
    NSLog(@"VPNid: %@",VPNid);
    
    //Save creds in memory for status query later
    memUserName = usernameLocal;
    memPassword = passwordLocal;
    
    //Check to see if we save the creds permenantly in the
    //keychain
    if([self isSaveCredsInKeychainChecked]){
        NSLog(@"Saving Creds");
        [myAuthAgent saveUsername:usernameLocal andPassword:passwordLocal];
        
    }else{
        NSLog(@"Not Saving Creds");
        [myAuthAgent CleanKeyChain];
        
    }
    
    
    
    //Call GetVPNConfig
    NSString *conf = [AxionAPI GetVPNConfig:VPNid withUser:usernameLocal andPass:passwordLocal];
    
    [BadCredsMsg setTextColor:[NSColor blackColor]];
    BadCredsMsg.stringValue = @"Initializing VPN Connection";
    
    
    //Invoke VPN issue
    if(!conf){
        NSLog(@"Invalid conf");
        [BadCredsMsg setTextColor:[NSColor redColor]];
        BadCredsMsg.stringValue = @"Failed to Download Configuration";
        //enable connect button
        [connectButton setEnabled:TRUE];
        
        return;
    }else{
        
        
        NSString *prefix = [NSString stringWithFormat:@"%@",geoArea];
        
        //Generate a good conf file in a tempoary path
        NSString *tmpPath = [self pathForTemporaryFileWithPrefix:prefix];
        
        //Dump the conf
        [conf writeToFile:tmpPath atomically:YES encoding:NSASCIIStringEncoding error:nil];
        
        NSArray *filePaths = [NSArray arrayWithObjects:tmpPath,nil];
        
        
        [[ConfigurationManager manager] installConfigurationsAxion: filePaths
                                           skipConfirmationMessage: YES
                                                 skipResultMessage: YES
                                                    notifyDelegate: YES];
        
        
        
        //Now wipe the file
        NSError *error;
        [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:&error];
        
        
        //enable connect button
        [connectButton setEnabled:TRUE];
        
        //Exit this screen
        bCloseWin = TRUE;
        
        
        dispatch_async(dispatch_get_main_queue(), ^{
            NSWindow *w = [self window];
            if(bCloseWin){
                NSLog(@"[AxionNetworkView:connectButtonPressed] Closing the Window");
                [w close];
            }else{
                NSLog(@"[AxionNetworkView:connectButtonPressed] NOT closing the Window");
                
            }
            
            
        });
        
        
    }

    
    
    
}



-(void)connectButtonPressed:(id)__unused sender
{
    NSLog(@"[AxionNetworkView:connectButtonPressed] Connect Button Pressed");
    //NSWindow *w = [self window];
    bCloseWin = FALSE;
    
    NSString *usernameLocal = nil;
    NSString *passwordLocal = nil;
    
    //Every time we start
      [BadCredsMsg setHidden:TRUE];
    
    //Check for Selected item
    NSInteger selectedRow = [VPNList indexOfSelectedItem];    //[VPNList selected][VPNTable selectedRow];
    
    NSLog(@"Selected Row is: %ld",selectedRow);
    
    if(selectedRow == -1){
        NSLog(@"Please select a VPN site");
        NSAlert *alert = [[NSAlert alloc] init];
        [alert addButtonWithTitle:@"OK"];
        [alert setMessageText:@"No Location Selected"];
        [alert setInformativeText:@"Please select a Location"];
        [alert setAlertStyle:NSCriticalAlertStyle];
        [alert runModal];
        return;
    }
    

    
    //Clear this out every time we try
    [BadCredsMsg setHidden:TRUE];

    
     //simulate checking creds
    dispatch_async(dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self GetAndLoadConfig:selectedRow];
        
        
    });
    
    return;
}


#pragma ComboBox Delegate Functions

// Returns the number of items that the data source manages for the combo box
- (NSInteger)numberOfItemsInComboBox:(NSComboBox *) aComboBox
{

    if(sites){
        return [sites count];
    }else{
        return 0;
    }
}

// Returns the object that corresponds to the item at the specified index in the combo box
- (id)comboBox:(NSComboBox *)aComboBox objectValueForItemAtIndex:(NSInteger)index
{
    
    NSDictionary *VPNSite = [sites objectAtIndex:index];
    NSString *Location = [VPNSite objectForKey:@"geo_area"];
    
    
    return Location;
}


@end
