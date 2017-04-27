//
//  SshTerminal.m
//  LibSshTest
//
//  Created by Denis Vincent on 2015-06-05.
//  Copyright (c) 2015 Denis Vincent. All rights reserved.
//

#import "SshTerminal.h"
#import "VT100TerminalView.h"
#import "SshConnection.h"


// Helper object.
@interface TunnelProperties : NSObject
{
    NSString* hostName;
    NSString* remoteHostName;
    SInt16 port;
    SInt16 remotePort;
    BOOL reverse;
}
@property(copy,nonatomic)NSString* hostName;
@property(assign)SInt16 port;
@property(copy,nonatomic)NSString* remoteHostName;
@property(assign)SInt16 remotePort;
@property(assign)BOOL reverse;
@end

@implementation TunnelProperties
@synthesize hostName;
@synthesize port;
@synthesize remoteHostName;
@synthesize remotePort;
@synthesize reverse;

- (void)dealloc
{
	[hostName release];
	[remoteHostName release];
	[hostName release];
	[super dealloc];
}

@end


// Private extension.
@interface SshTerminal () <SshConnectionEventDelegate>

@end


// Implementation.
@implementation SshTerminal

@synthesize hostName;
@synthesize userName;
@synthesize keyFilePath;
@synthesize columnCount;
@synthesize state;
@synthesize port;
@synthesize x11Forwarding;
@synthesize x11Display;
@synthesize x11Authentication;
@synthesize x11AuthorityFile;
@synthesize internetProtocol;
@synthesize verbose;
@synthesize verbosityLevel;
@synthesize agentForwarding;
@synthesize useAgent;
@synthesize keepAliveTime;


-(void)setPassword:(NSString *)string
{
    password = [string copy];
}


-(void)setKeyFilePassword:(NSString *)string
{
    keyFilePassword = [string copy];
}


-(void)addForwardTunnelWithPort:(SInt16)newPort onHost:(NSString *)newHostName andRemotePort:(SInt16)newRemotePort onRemoteHost:(NSString *)newRemoteHostName
{
    TunnelProperties* tunnel = [TunnelProperties new];
    tunnel.port = newPort;
    tunnel.hostName = newHostName;
    tunnel.remotePort = newRemotePort;
    tunnel.remoteHostName = newRemoteHostName;
    tunnel.reverse = NO;
    [tunnels addObject:tunnel];
    [tunnel release];
}


-(void)addReverseTunnelWithPort:(SInt16)newPort onHost:(NSString *)newHostName andRemotePort:(SInt16)newRemotePort onRemoteHost:(NSString *)newRemoteHostName
{
    TunnelProperties* tunnel = [TunnelProperties new];
    tunnel.port = newPort;
    tunnel.hostName = newHostName;
    tunnel.remotePort = newRemotePort;
    tunnel.remoteHostName = newRemoteHostName;
    tunnel.reverse = YES;
    [tunnels addObject:tunnel];
    [tunnel release];
}


-(void)clearAllTunnels
{
    [tunnels removeAllObjects];
}


-(void)connect
{
    if (state != sshTerminalDisconnected)
    {
        return;
    }
    state = sshTerminalConnected;
    
    [connection release];
    connection = [[SshConnection alloc] init];
    [connection setEventDelegate:self];
    [terminalView setConnection:connection];

    int family = PF_UNSPEC;
    if (internetProtocol == sshTerminalIpv4)
    {
        family = PF_INET;
    }
    else if (internetProtocol == sshTerminalIpv6)
    {
        family = PF_INET6;
    }
    [connection setHost:hostName port:port protocol:family];
    [connection setUser:userName];
    [connection setKeyFilePath:[keyFilePath stringByExpandingTildeInPath] withPassword:keyFilePassword];
    [connection setPassword:password];
    int tunnelCount = (int)[tunnels count];
    for (int i = 0; i < tunnelCount; i++)
    {
        TunnelProperties* tunnel = [tunnels objectAtIndex:i];
        if (tunnel.reverse == NO)
        {
            [connection addForwardTunnelPort:tunnel.port host:tunnel.hostName remotePort:tunnel.remotePort remoteHost:tunnel.remoteHostName];
        }
        else
        {
            [connection addReverseTunnelPort:tunnel.port host:tunnel.hostName remotePort:tunnel.remotePort remoteHost:tunnel.remoteHostName];
        }
    }
    [connection setX11Forwarding:x11Forwarding withDisplay:x11Display];
    [connection setVerbose:verbose withLevel:verbosityLevel];
    [connection setAgentForwarding:agentForwarding];
    [connection setUseAgent:useAgent];
    [connection setKeepAliveTime:keepAliveTime];
    
    [terminalView initScreen];
	
    [connection startConnection];
}


-(void)resume
{
    if (connection != nil)
    {
        if (state != sshTerminalPaused)
        {
            return;
        }
        state = sshTerminalConnected;
        [connection resume:YES andSaveHost:NO];
    }
}


-(void)resumeAndRememberServer
{
    if (connection != nil)
    {
        if (state != sshTerminalPaused)
        {
            return;
        }
        state = sshTerminalConnected;
        [connection resume:YES andSaveHost:YES];
    }
}


-(void)disconnect
{
    if (connection != nil)
    {
        if (state == sshTerminalDisconnected)
        {
            return;
        }
        state = sshTerminalDisconnected;
        [connection endConnection];
    }
}


-(void)send:(NSString *)string
{
    if (connection != nil)
    {
        if (state != sshTerminalConnected)
        {
            return;
        }
        const char* utf8String = [string UTF8String];
        [connection writeFrom:(const UInt8*)utf8String length:(int)strlen(utf8String)];
    }
}


-(void)setFontWithName:(NSString *)fontName size:(CGFloat)fontSize
{
	[terminalView.screen setFontWithname:fontName size:fontSize];
	NSSize size = [self contentSize];
	[terminalView setTerminalSize:size];
	[terminalView needsDisplay];
}


-(void)setEventDelegate:(id)delegate
{
    eventDelegate = delegate;
}


-(void)signalError:(int)code
{
    switch (code)
    {
        case CONNECTED:
        {
            if (tunnels.count == 0)
            {
                [terminalView setCursorVisible:YES];
            }
            if ([eventDelegate respondsToSelector:@selector(connected)])
            {
                [eventDelegate connected];
            }
            break;
        }
            
        case DISCONNECTED:
        {
            state = sshTerminalDisconnected;
            [terminalView setCursorVisible:NO];
            if ([eventDelegate respondsToSelector:@selector(disconnected)])
            {
                [eventDelegate disconnected];
            }
            connection = nil;
            break;
        }
            
        case SERVER_KEY_CHANGED:
        case SERVER_KEY_FOUND_OTHER:
        case SERVER_NOT_KNOWN:
        {
            state = sshTerminalPaused;
            if ([eventDelegate respondsToSelector:@selector(serverMismatch:)])
            {
                NSString* fingerPrint = [connection fingerPrint];
                [eventDelegate serverMismatch:fingerPrint];
            }
            break;
        }
            
        default:
        {
            if ([eventDelegate respondsToSelector:@selector(error:)])
            {
                [eventDelegate error:(int)code];
            }
            break;
        }
    }
}


-(void)adjustTerminalSize
{
    NSSize size = [self contentSize];
    NSRect terminalRect = [terminalView frame];
    terminalRect.size.width = size.width;
    [terminalView setFrameSize:terminalRect.size];
    [terminalView setTerminalSize:size];
}


-(void)setFrame:(NSRect)frame
{
    [super setFrame:frame];
    [self adjustTerminalSize];
}


-(void)setFrameSize:(NSSize)newSize
{
    [super setFrameSize:newSize];
    [self adjustTerminalSize];
}


-(void)initSubclassMembers
{
    state = sshTerminalDisconnected;
    port = 22;
    tunnels = [NSMutableArray new];
    
    [self setAutoresizesSubviews:YES];
    [self setHasVerticalScroller:YES];
    [self setHasHorizontalScroller:NO];
    [self setAutoresizesSubviews:YES];
    
    NSClipView* clip = [[NSClipView alloc] init];
    [self setContentView:clip];
    [clip release];

    NSRect rect;
    rect.origin = NSMakePoint(0, 0);
    rect.size = self.contentSize;

    terminalView = [[VT100TerminalView alloc] initWithFrame:rect];
    [terminalView setEditable:NO];
    [self adjustTerminalSize];
    
    [self setDocumentView:terminalView];
}


-(SshTerminal*)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self != nil)
    {
        [self initSubclassMembers];
    }
    
    return self;
}


-(instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self != nil)
    {
        [self initSubclassMembers];
    }
    
    return self;
}


-(SshTerminal*)init
{
    return [self initWithFrame:NSMakeRect(0, 0, 0, 0)];
}


- (void)dealloc
{
	[x11AuthorityFile release];
	[x11Authentication release];
	[keyFilePath release];
	[hostName release];
	[userName release];
	[x11Display release];
	[super dealloc];
}

@end
