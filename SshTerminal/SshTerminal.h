//
//  SshTerminal.h
//  SshTerminal
//
//  Created by Denis Vincent on 2015-06-29.
//  Copyright (c) 2015 Denis Vincent. All rights reserved.
//

#import <Cocoa/Cocoa.h>

//! Project version number for SshTerminal.
FOUNDATION_EXPORT double SshTerminalVersionNumber;

//! Project version string for SshTerminal.
FOUNDATION_EXPORT const unsigned char SshTerminalVersionString[];

// In this header, you should import all the public headers of your framework using statements like #import <SshTerminal/PublicHeader.h>


enum
{
    sshTerminalDisconnected,
    sshTerminalConnected,
    sshTerminalPaused,
};


@protocol SshTerminalEvent <NSObject>
@optional
-(void)connected;
-(void)disconnected;
-(void)serverMismatch:(NSString*)fingerPrint;   // The connection process has been suspended because the server is either unknown or has changed. Must call -(void)resume or -(void)resumeAndRememberServer or -(void)disconnect.
-(void)error:(int)code;

@end


@interface SshTerminal : NSScrollView
{
    NSString* password;
    NSString* hostName;
    NSString* userName;
    NSString* keyFilePath;
    NSString* keyFilePassword;
    UInt16 port;
    int columnCount;
    int state;
    id<SshTerminalEvent> eventDelegate;
}

-(void)setPassword:(NSString *)string;
-(void)setKeyFilePassword:(NSString *)string;

@property(copy,nonatomic)NSString* hostName;
@property(assign)UInt16 port;
@property(copy,nonatomic)NSString* userName;
@property(copy,nonatomic)NSString* keyFilePath;

@property(assign)int columnCount;
@property(readonly)int state;

-(void)setEventDelegate:(id<SshTerminalEvent>) delegate;
-(void)connect;
-(void)resume;
-(void)resumeAndRememberServer;
-(void)disconnect;


@end
