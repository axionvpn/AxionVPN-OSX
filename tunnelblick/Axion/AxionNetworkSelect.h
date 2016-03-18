//
//  AxionNetworkSelect.h
//  Tunnelblick
//
//  Created by User Name on 10/11/15.
//
//

#import <Cocoa/Cocoa.h>
#import "AxionNetworkView.h"

@interface AxionNetworkSelect : NSWindowController <NSComboBoxDelegate,NSComboBoxDataSource>{
    IBOutlet AxionNetworkView *NetworkView;

}



@end
