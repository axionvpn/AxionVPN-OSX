//
//  AxionNetworkSelect.m
//  Tunnelblick
//
//  Created by User Name on 10/11/15.
//
//

#import "AxionNetworkSelect.h"

@interface AxionNetworkSelect ()

@end

@implementation AxionNetworkSelect


extern NSString *memUserName;          //User name cached in memory only
extern NSString *memPassword;          //Password cached in memory only


- (id)initWithCoder:(NSCoder*)coder
{
    self = [super initWithCoder:coder];
    
  
    
    return self;
}


- (void)windowDidLoad {
    [super windowDidLoad];
    
    
    NSLog(@"[AxionNetworkSelect:windowDidLoad] Called");
    
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
}

- (void)windowWillLoad{
    
    [super windowWillLoad];
    
    NSLog(@"[AxionNetworkSelect:windowWillLoad] Called");

}










@end
