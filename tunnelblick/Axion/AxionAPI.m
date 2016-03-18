//
//  AxionVPN.m
//  AxionVPN
//
//  Created by User Name
//  Copyright © 2015 User Name. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "AxionAPI.h"





@implementation AxionAPI


+(BOOL)ProcessResult:(NSNumber *)result{
    
    NSAlert *alert = [[NSAlert alloc] init];
 
    
    
    if( [result intValue] == 0){
        return TRUE;
    }else if([result intValue] == 1){
        [alert addButtonWithTitle:@"OK"];
        [alert setMessageText:@"Invalid Username or Password"];
        [alert setInformativeText:@"Please check your username or password and try again"];
        [alert setAlertStyle:NSCriticalAlertStyle];
        [alert runModal];
        
    }else if([result intValue] == 2){
        
        [alert addButtonWithTitle:@"OK"];
        [alert setMessageText:@"Account Not Activated"];
        [alert setInformativeText:@"Please check for an activation e-mail."];
        [alert setAlertStyle:NSCriticalAlertStyle];
        [alert runModal];
    }
    else if([result intValue] == 3){
            
    }else{
        
        [alert addButtonWithTitle:@"OK"];
        [alert setMessageText:@"Uknonwn Error"];
        NSString *infoString = [NSString stringWithFormat:@"Unknown Error %@ occurred",result];
        [alert setInformativeText:infoString];
        [alert setAlertStyle:NSCriticalAlertStyle];
        [alert runModal];
    }
    
    return FALSE;
    
}



+ (BOOL) ValidateCreds:(NSString *)user andPass:(NSString *)pass {
 
    BOOL bRetVal = FALSE;
    NSAlert *alert = [[NSAlert alloc] init];
    
    
    NSLog(@"[AxionAPI:ValidateCreds] Called\n");
    
    
    
    NSURL *getConfigURL = [NSURL URLWithString:@"https://axionvpn.com/api/get-info"];
    
    NSString *paramString = [NSString stringWithFormat:@"username=%@&password=%@",user,pass];
    NSLog(@"[AxionAPI:ValidateCreds] params: %@",paramString);
    
    
    NSString* encodedParams = [paramString stringByAddingPercentEscapesUsingEncoding:
                               NSUTF8StringEncoding];
    NSLog(@"[AxionAPI:ValidateCreds] Encoded Params: %@",encodedParams);
    
    
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:getConfigURL
                                                           cachePolicy:NSURLRequestUseProtocolCachePolicy
                                                       timeoutInterval:60.0];
    
    
    
    
    [request setHTTPMethod:@"POST"];
    [request setValue:[NSString stringWithFormat:@"%ld", encodedParams.length] forHTTPHeaderField:@"Content-Length"];
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setHTTPBody:[encodedParams dataUsingEncoding:NSUTF8StringEncoding]];
    
    NSError *error = nil;
    
    NSHTTPURLResponse *response = nil;
    NSData *responseData = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
    
    
    if(response){
        NSLog(@"[AxionAPI:ValidateCreds] Valid Response");
        
        if(!error){
            NSLog(@"[AxionAPI:ValidateCreds] Successful request");
            
            
            NSDictionary *data = [NSJSONSerialization
                                  JSONObjectWithData: responseData
                                  options: NSJSONReadingMutableContainers
                                  error: &error];
            
            
            NSLog(@"[AxionAPI:ValidateCreds]response %@", data);
            
            NSNumber *result = [data objectForKey:@"result"];
            NSLog(@"Result: %@",result);
            if( [result intValue] == 0){
                bRetVal = TRUE;
            }else if([result intValue] == 1){
                //[alert addButtonWithTitle:@"OK"];
                //[alert setMessageText:@"Invalid Username or Password"];
                //[alert setInformativeText:@"Please check your username or password and try again"];
                //[alert setAlertStyle:NSCriticalAlertStyle];
               // [alert runModal];
                
            }else if([result intValue] == 2){
                
                [alert addButtonWithTitle:@"OK"];
                [alert setMessageText:@"Account Not Activated"];
                [alert setInformativeText:@"Please check for an activation e-mail."];
                [alert setAlertStyle:NSCriticalAlertStyle];
                [alert runModal];
            }
            else{
                bRetVal = TRUE;
            }
            
            
        }
    }
    
    
    NSLog(@"[AxionAPI:ValidateCreds] Returning\n");
    
    
    return bRetVal;
}



+ (NSDictionary *) GetVPNStatus:(NSString *)user andPass:(NSString *) pass{
    NSDictionary *statusString = nil;
    
    NSLog(@"[getVPNConfig] Called\n");
    
    
    NSURL *getConfigURL = [NSURL URLWithString:@"https://axionvpn.com/api/get-info"];
    
    NSString *paramString = [NSString stringWithFormat:@"username=%@&password=%@",user,pass];
    
    NSLog(@"params: %@",paramString);
    NSString* encodedParams = [paramString stringByAddingPercentEscapesUsingEncoding:
                               NSUTF8StringEncoding];
    
    NSLog(@"Encoded Params: %@",encodedParams);
    
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:getConfigURL
                                                           cachePolicy:NSURLRequestUseProtocolCachePolicy
                                                       timeoutInterval:60.0];
    
    
    
    
    [request setHTTPMethod:@"POST"];
    [request setValue:[NSString stringWithFormat:@"%ld", encodedParams.length] forHTTPHeaderField:@"Content-Length"];
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setHTTPBody:[encodedParams dataUsingEncoding:NSUTF8StringEncoding]];
    
    NSError *error = nil;
    
    NSHTTPURLResponse *response = nil;
    NSData *responseData = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
    
    
    if(response){
        NSLog(@"Valid Response");
        
        if(!error){
            NSLog(@"successful request");
            
            
            NSDictionary *data = [NSJSONSerialization
                                  JSONObjectWithData: responseData
                                  options: NSJSONReadingMutableContainers
                                  error: &error];
            
            
            NSLog(@"response %@", data);
            
            NSNumber *result = [data objectForKey:@"result"];
            NSLog(@"Result: %@",result);
            
            
            if( [self ProcessResult:result] ){
                statusString = data;
            }
            
            

            
        }
    }
    
    
    NSLog(@"[getVPNStatis] Returning\n");
    
    
    return statusString;
}


//
//Retreive the VPN Cofnig from the Axion Site
//
+ (NSString *) GetVPNConfig:(NSString *)VPNId withUser:(NSString *)user andPass:(NSString *) pass{
    NSLog(@"[getVPNConfig] Called with %@\n",VPNId);
    
    NSString *conf = nil;

    
    NSURL *getConfigURL = [NSURL URLWithString:@"https://axionvpn.com/api/get-config"];
    
    NSString *paramString = [NSString stringWithFormat:@"id=%@&username=%@&password=%@",VPNId,user,pass];
    
    NSLog(@"params: %@",paramString);
    NSString* encodedParams = [paramString stringByAddingPercentEscapesUsingEncoding:
                            NSUTF8StringEncoding];
    
    NSLog(@"Encoded Params: %@",encodedParams);
    
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:getConfigURL
                                                           cachePolicy:NSURLRequestUseProtocolCachePolicy
                                                       timeoutInterval:60.0];
    
    
    
    
    [request setHTTPMethod:@"POST"];
    [request setValue:[NSString stringWithFormat:@"%ld", encodedParams.length] forHTTPHeaderField:@"Content-Length"];
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setHTTPBody:[encodedParams dataUsingEncoding:NSUTF8StringEncoding]];
    
    NSError *error = nil;
    
    NSHTTPURLResponse *response = nil;
    NSData *responseData = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
    
    
    if(response){
        NSLog(@"Valid Response");
        
        if(!error){
            NSLog(@"successful request");
            
            
            NSDictionary *data = [NSJSONSerialization
                                  JSONObjectWithData: responseData
                                  options: NSJSONReadingMutableContainers
                                  error: &error];
            
            
            NSLog(@"response %@", data);
            
            NSNumber *result = [data objectForKey:@"result"];
            NSLog(@"Result: %@",result);
            

            [self ProcessResult:result];
            
            
            conf = [data objectForKey:@"conf"];
            
        }
    }
    
    
    
    
    
    NSLog(@"[getVPNConfig] Returning\n");
    
    
    
    return conf;
    
}

//
// Get the list of VPN's to populate the main site
//

+ (NSArray *) getVPNList{
    NSLog(@"[getVPNList] Called\n");
    
    NSURL *getVPNSURL = [NSURL URLWithString:@"https://axionvpn.com/api/get-vpns"];
  
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:getVPNSURL
                                                           cachePolicy:NSURLRequestUseProtocolCachePolicy
                                                       timeoutInterval:60.0];
    
    [request setHTTPMethod:@"POST"];
    
    NSError *error = nil;
    
    NSHTTPURLResponse *response = nil;
    NSData *responseData = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
    
    
    if(response){
        NSLog(@"Valid Response");
        
        if(!error){
            NSLog(@"successful request");
            
            
            NSDictionary *data = [NSJSONSerialization
                                  JSONObjectWithData: responseData
                                  options: NSJSONReadingMutableContainers
                                  error: &error];
            
            
            NSLog(@"response %@", data);
            
            //Now walk thourg "VPNS" and add each to an array
            NSMutableArray *rawSites = data[@"vpns"];
            
            return rawSites;
            
            
        }else{
            NSLog(@"failed request");
        }
        
        
    }
    
    
    NSLog(@"[getVPNList] Returning");
    return nil;
    
    
}






@end