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


@class VT100TerminalView;
@class TelnetConnection;

enum
{
    telnetTerminalIpDefault,
    telnetTerminalIpv4,
    telnetTerminalIpv6,
};

enum
{
    telnetTerminalProxyNone,
    telnetTerminalProxySocks4,
    telnetTerminalProxySocks5,
    telnetTerminalProxyHttp,
    telnetTerminalProxyTelnet,
    telnetTerminalProxyLocal,
};

enum
{
    telnetTerminalDnsLookupAuto,
    telnetTerminalDnsLookupProxyEnd,
    telnetTerminalDnsLookupLocal,
};

@interface TelnetTerminal : NSScrollView
{
    VT100TerminalView* terminalView;
    TelnetConnection* connection;
    
	NSColor* defaultBackground;
	NSColor* defaultForeground;
	NSColor* cursorBackground;
	NSColor* cursorForeground;
	NSColor* colors[16];
	
	NSMutableArray* syntaxColoringItems;
	BOOL syntaxColoringChangeMade;
	BOOL syntaxColoringScreenInitiated;
	
    NSString* password;
    NSString* hostName;
    NSString* userName;
    NSString* proxyHost;
    NSString* proxyUser;
    NSString* proxyPassword;
    NSString* proxyConnectCommand;
    NSString* proxyExclusion;
    UInt16 port;
    UInt16 proxyPort;
    int proxyDnsLookup;
    int internetProtocol;
    int proxyType;
    int columnCount;
    int state;
    BOOL proxyIncludeLocal;
    id<TelnetTerminalEvent> eventDelegate;
}

@property(copy,nonatomic)NSString* hostName;   // Host name or IP address.
@property(assign)UInt16 port;
-(void)setPassword:(NSString *)string;
@property(copy,nonatomic)NSString* userName;
@property(assign)int columnCount;
@property(assign)int internetProtocol;
@property(assign)int proxyType;
@property(copy,nonatomic)NSString* proxyHost;
@property(assign)UInt16 proxyPort;
@property(copy,nonatomic)NSString* proxyUser;
@property(copy,nonatomic)NSString* proxyPassword;
@property(copy,nonatomic)NSString* proxyConnectCommand;
@property(copy,nonatomic)NSString* proxyExclusion;
@property(assign)int proxyDnsLookup;
@property(assign)BOOL proxyIncludeLocal;

@property(readonly)int state;

-(void)setDefaultBackgroundRed:(UInt8)r green:(UInt8)g blue:(UInt8)b;
-(void)setDefaultForegroundRed:(UInt8)r green:(UInt8)g blue:(UInt8)b;
-(void)setCursorBackgroundRed:(UInt8)r green:(UInt8)g blue:(UInt8)b;
-(void)setCursorForegroundRed:(UInt8)r green:(UInt8)g blue:(UInt8)b;
-(void)setColor:(int)index red:(UInt8)r green:(UInt8)g blue:(UInt8)b;

-(void)setFontWithName:(NSString *)fontName size:(CGFloat)fontSize;
-(void)setEventDelegate:(id<TelnetTerminalEvent>) delegate;
-(void)connect;
-(void)disconnect;
-(void)send:(NSString *)string;

-(void)syntaxColoringAddOrUpdateItem:(NSString*)keyword itemBackColor:(int)backColor itemTextColor:(int)textColor itemIsCompleteWord:(BOOL)isCompleteWord itemIsCaseSensitive:(BOOL)isCaseSensitive itemIsUnderlined:(BOOL)isUnderlined;
-(void)syntaxColoringDeleteItem:(NSString*)keyword;
-(void)syntaxColoringEnableItem:(NSString*)keyword;
-(void)syntaxColoringDisableItem:(NSString*)keyword;
-(void)syntaxColoringDeleteAllItems;
-(void)syntaxColoringEnableAllItems;
-(void)syntaxColoringDisableAllItems;
-(void)syntaxColoringApplyChanges;

@end
