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

enum
{
    sshTerminalIpDefault,
    sshTerminalIpv4,
    sshTerminalIpv6,
};

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
    NSString* x11Authentication;
    NSString* x11AuthorityFile;
    UInt16 port;
    BOOL x11Forwarding;
    BOOL verbose;
    BOOL agentForwarding;
    BOOL useAgent;
    int internetProtocol;
    int columnCount;
    int state;
	int verbosityLevel;
    int keepAliveTime;
    id<SshTerminalEvent> eventDelegate;
    NSMutableArray* tunnels;
	
	NSColor* defaultBackground;
	NSColor* defaultForeground;
	NSColor* cursorBackground;
	NSColor* cursorForeground;
	NSColor* colors[16];
	
	NSMutableArray* syntaxColoringItems;
	BOOL syntaxColoringChangeMade;
	BOOL syntaxColoringScreenInitiated;
}

@property(copy,nonatomic)NSString* hostName;   // Host name or IP address.
@property(assign)UInt16 port;
-(void)setPassword:(NSString *)string;
@property(copy,nonatomic)NSString* userName;
@property(assign)BOOL useAgent;
@property(copy,nonatomic)NSString* keyFilePath;
-(void)setKeyFilePassword:(NSString *)string;
@property(assign)int columnCount;
-(void)addForwardTunnelWithPort:(SInt16)port onHost:(NSString*)hostName andRemotePort:(SInt16)remotePort onRemoteHost:(NSString*)remoteHostName;
-(void)addReverseTunnelWithPort:(SInt16)port onHost:(NSString*)hostName andRemotePort:(SInt16)remotePort onRemoteHost:(NSString*)remoteHostName;
-(void)clearAllTunnels;
@property(assign)BOOL x11Forwarding;
@property(copy,nonatomic)NSString* x11Display;
@property(copy,nonatomic)NSString* x11Authentication;   // Either @"MIT-MAGIC-COOKIE-1" or @"XDM-AUTHORIZATION-1".
@property(copy,nonatomic)NSString* x11AuthorityFile;
@property(assign)int internetProtocol;
@property(assign)BOOL verbose;
@property(assign)BOOL agentForwarding;
@property(assign)int verbosityLevel;
@property(readonly)int state;
@property(assign)int keepAliveTime;   // Zero equals: keepalive off. Otherwise: time between keepalives in seconds.

-(void)setDefaultBackgroundRed:(UInt8)r green:(UInt8)g blue:(UInt8)b;
-(void)setDefaultForegroundRed:(UInt8)r green:(UInt8)g blue:(UInt8)b;
-(void)setCursorBackgroundRed:(UInt8)r green:(UInt8)g blue:(UInt8)b;
-(void)setCursorForegroundRed:(UInt8)r green:(UInt8)g blue:(UInt8)b;
-(void)setColor:(int)index red:(UInt8)r green:(UInt8)g blue:(UInt8)b;

-(void)setFontWithName:(NSString*)fontName size:(CGFloat)fontSize;
-(void)setEventDelegate:(id<SshTerminalEvent>) delegate;
-(void)connect;
-(void)resume;
-(void)resumeAndRememberServer;
-(void)disconnect;
-(void)send:(NSString*)string;

-(void)syntaxColoringAddOrUpdateItem:(NSString*)keyword itemBackColor:(int)backColor itemTextColor:(int)textColor itemIsCompleteWord:(BOOL)isCompleteWord itemIsCaseSensitive:(BOOL)isCaseSensitive itemIsUnderlined:(BOOL)isUnderlined;
-(void)syntaxColoringDeleteItem:(NSString*)keyword;
-(void)syntaxColoringEnableItem:(NSString*)keyword;
-(void)syntaxColoringDisableItem:(NSString*)keyword;
-(void)syntaxColoringDeleteAllItems;
-(void)syntaxColoringEnableAllItems;
-(void)syntaxColoringDisableAllItems;
-(void)syntaxColoringApplyChanges;


@end
