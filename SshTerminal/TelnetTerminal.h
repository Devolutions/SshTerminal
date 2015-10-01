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
    
    NSString* password;
    NSString* hostName;
    NSString* userName;
    NSString* proxyHost;
    NSString* proxyUser;
    NSString* proxyPassword;
    UInt16 port;
    UInt16 proxyPort;
    int proxyDnsLookup;
    int internetProtocol;
    int proxyType;
    int columnCount;
    int state;
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
@property(assign)int proxyDnsLookup;

@property(readonly)int state;

-(void)setEventDelegate:(id<TelnetTerminalEvent>) delegate;
-(void)connect;
-(void)disconnect;


@end
