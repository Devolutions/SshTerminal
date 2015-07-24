//
//  TelnetConnection.h
//  SshTerminal
//
//  Created by Denis Vincent on 2015-07-22.
//  Copyright (c) 2015 Denis Vincent. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "VT100Connection.h"
#import "NetworkHelpers.h"


enum TelnetConnectionEvent
{
    tceFatalError,
    
    tceConnected,
    tceDisconnected,
};


@protocol TelnetConnectionEventDelegate <NSObject>

-(void)signalError:(int)code;

@end


@interface TelnetConnection : NSObject <VT100Connection>

// Methods called from the UI thread.
-(void)setHost:(NSString*)newHost;
-(void)setPort:(SInt16)newPort;
-(void)setUser:(NSString*)newUser;
-(void)setPassword:(NSString*)newPassword;
-(void)setWidth:(int)newWidth;

-(void)setEventDelegate:(id<TelnetConnectionEventDelegate>)newEventDelegate;

-(int)writeFrom:(const UInt8*)buffer length:(int)count;
-(void)startConnection;
-(void)endConnection;

@end
