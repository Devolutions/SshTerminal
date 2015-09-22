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


@class VT100TerminalView;
@class SshConnection;

@interface SshTerminal : NSScrollView
{
    VT100TerminalView* terminalView;
    SshConnection* connection;
    
    NSString* password;
    NSString* hostName;
    NSString* userName;
    NSString* keyFilePath;
    NSString* keyFilePassword;
    NSString* x11Display;
    UInt16 port;
    BOOL x11Forwarding;
    int columnCount;
    int state;
    id<SshTerminalEvent> eventDelegate;
    NSMutableArray* tunnels;
}

@property(copy,nonatomic)NSString* hostName;   // Host name or IP address.
@property(assign)UInt16 port;
-(void)setPassword:(NSString *)string;
@property(copy,nonatomic)NSString* userName;
@property(copy,nonatomic)NSString* keyFilePath;
-(void)setKeyFilePassword:(NSString *)string;
@property(assign)int columnCount;
-(void)addForwardTunnelWithPort:(SInt16)port onHost:(NSString*)hostName andRemotePort:(SInt16)remotePort onRemoteHost:(NSString*)remoteHostName;
-(void)addReverseTunnelWithPort:(SInt16)port onHost:(NSString*)hostName andRemotePort:(SInt16)remotePort onRemoteHost:(NSString*)remoteHostName;
-(void)clearAllTunnels;
@property(assign)BOOL x11Forwarding;
@property(copy,nonatomic)NSString* x11Display;

@property(readonly)int state;

-(void)setEventDelegate:(id<SshTerminalEvent>) delegate;
-(void)connect;
-(void)resume;
-(void)resumeAndRememberServer;
-(void)disconnect;
-(void)send:(NSString*)string;


@end
