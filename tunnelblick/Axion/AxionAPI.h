//
//  AxionAPI.h
//  AxionAPI
//

//  Copyright © 2015 User Name. All rights reserved.
//

#import <Cocoa/Cocoa.h>

typedef NS_ENUM(NSInteger, ResultCode){
    Success = 0,
    InvalidPassword,
    InvalidUsername,
    Disconnected
};



@interface AxionAPI : NSObject

+ (NSArray *) getVPNList;

+ (NSString *) GetVPNConfig: (NSString *)VPNId withUser:(NSString *)user andPass:(NSString *) pass;

+ (NSDictionary *) GetVPNStatus:(NSString *)user andPass:(NSString *) pass;

+ (BOOL) ValidateCreds:(NSString *)user andPass:(NSString *)pass;

@end




