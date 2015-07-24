//
//  TelnetTerminal.h
//  SshTerminal
//
//  Created by Denis Vincent on 2015-07-22.
//  Copyright (c) 2015 Denis Vincent. All rights reserved.
//

#import <Cocoa/Cocoa.h>


enum
{
    telnetTerminalDisconnected,
    telnetTerminalConnected,
    telnetTerminalPaused,
};


@protocol TelnetTerminalEvent <NSObject>
@optional
-(void)connected;
-(void)disconnected;
-(void)error:(int)code;

@end


@interface TelnetTerminal : NSScrollView

@property(copy,nonatomic)NSString* hostName;   // Host name or IP address.
@property(assign)UInt16 port;
-(void)setPassword:(NSString *)string;
@property(copy,nonatomic)NSString* userName;
@property(assign)int columnCount;

@property(readonly)int state;

-(void)setEventDelegate:(id<TelnetTerminalEvent>) delegate;
-(void)connect;
-(void)disconnect;


@end
