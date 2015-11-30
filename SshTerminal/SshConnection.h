//
//  SshConnection.h
//  LibSshTest
//
//  Created by Denis Vincent on 2015-06-03.
//  Copyright (c) 2015 Denis Vincent. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "VT100Connection.h"
#import "SshFoundation.h"
#import "SshTunnel.h"
#import "SshTunnelConnection.h"


#define INPUT_BUFFER_SIZE 1024
#define OUTPUT_BUFFER_SIZE 1024

enum ConnectionEvent
{
    FATAL_ERROR,
    OUT_OF_MEMORY_ERROR,
    TUNNEL_ERROR,
    CONNECTION_ERROR,
    SERVER_KEY_CHANGED,
    SERVER_KEY_FOUND_OTHER,
    SERVER_NOT_KNOWN,
    SERVER_FILE_NOT_FOUND,
    SERVER_ERROR,
    PASSWORD_AUTHENTICATION_DENIED,
    KEY_FILE_NOT_FOUND_OR_DENIED,
    CHANNEL_ERROR,
    CHANNEL_RESIZE_ERROR,
    X11_ERROR,
    
    CONNECTED,
    DISCONNECTED,
};


@protocol SshConnectionEventDelegate <NSObject>

-(void)signalError:(int)code;

@end


@interface SshConnection : NSObject <VT100Connection>
{
    ssh_session session;
    ssh_channel channel;
    BOOL useKeyAuthentication;
    BOOL x11Forwarding;
    NSString* host;
    NSString* password;
    NSString* keyFilePassword;
    NSString* keyFilePath;
    NSString* x11DisplayName;
    NSString* x11Host;
    int x11DisplayNumber;
    int x11ScreenNumber;
    int width;
    int height;
    int internetProtocol;
    BOOL verbose;
    
    UInt8 inBuffer[INPUT_BUFFER_SIZE];
    UInt8 outBuffer[OUTPUT_BUFFER_SIZE];
    int inIndex;
    int outIndex;
    
    dispatch_queue_t queue;
    dispatch_queue_t mainQueue;
    dispatch_source_t readSource;
    NSMutableArray* forwardTunnels;
    NSMutableArray* reverseTunnels;
    NSMutableArray* tunnelConnections;
    
    id<VT100TerminalDataDelegate> dataDelegate;
    id<SshConnectionEventDelegate> eventDelegate;
}

// Methods called from the UI thread.
-(void)setHost:(NSString*)newHost port:(UInt16)newPort protocol:(int)newProtocol;
-(void)setUser:(NSString*)newUser;
-(void)setKeyFilePath:(NSString*)newKeyFilePath withPassword:(NSString*)newPassword;
-(void)setPassword:(NSString*)newPassword;
-(void)setVerbose:(BOOL)newVerbose;

-(void)addForwardTunnelPort:(SInt16)newPort host:(NSString*)newHost remotePort:(SInt16)newRemotePort remoteHost:(NSString*)newRemoteHost;
-(void)addReverseTunnelPort:(SInt16)newPort host:(NSString*)newHost remotePort:(SInt16)newRemotePort remoteHost:(NSString*)newRemoteHost;

-(void)setX11Forwarding:(BOOL)enable withDisplay:(NSString*)display;

-(void)setEventDelegate:(id<SshConnectionEventDelegate>)newEventDelegate;

-(void)resume:(BOOL)isResuming andSaveHost:(BOOL)needsSaveHost;
-(void)startConnection;
-(void)endConnection;
-(NSString*)fingerPrint;

// Methods called from the private queue thread.
-(void)connect;
-(void)authenticateServer;
-(void)authenticateUser;
-(void)openTerminalChannel;
-(void)newTerminalDataAvailable;
-(void)newSshDataAvailable;
-(void)newTunnelConnection:(SshTunnel*)tunnel;
-(void)closeAllChannels;
-(void)disconnect;


@end
