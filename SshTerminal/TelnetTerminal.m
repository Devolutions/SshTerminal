//
//  SshTerminal.m
//  LibSshTest
//
//  Created by Denis Vincent on 2015-06-05.
//  Copyright (c) 2015 Denis Vincent. All rights reserved.
//

#import "TelnetTerminal.h"
#import "VT100TerminalView.h"
#import "TelnetConnection.h"
#import "ProxySocks4.h"
#import "ProxySocks5.h"
#import "ProxyHttp.h"
#import "ProxyTelnet.h"


BOOL isMatch(NSString* host, NSString* excluded)
{
    NSRange searchRange;
    NSRange wildCardRange;
    NSRange range;
    
    NSUInteger hostLength = [host length];
    NSUInteger hostLocation = 0;
    NSUInteger excludedLength = [excluded length];
    NSUInteger excludedLocation = 0;
    while (excludedLocation < excludedLength)
    {
        searchRange = NSMakeRange(excludedLocation, excludedLength - excludedLocation);
        wildCardRange = [excluded rangeOfString:@"*" options:0 range:searchRange];
        if (wildCardRange.length == 0)
        {
            if (excludedLocation == 0)
            {
                // No wild card in the excluded string: do a simple compare.
                if ([host compare:excluded] == NSOrderedSame)
                {
                    return YES;
                }
                return NO;
            }
            else
            {
                // This is the last substring of the exclusion pattern:
                wildCardRange.location = excludedLength;
            }
        }
        
        range.location = excludedLocation;
        range.length = wildCardRange.location - excludedLocation;
        if (range.length == 0)
        {
            // No substring between the last wild card and this one:
            excludedLocation++;
            continue;
        }
        
        if (range.location == 0)
        {
            // This substring must be found at the beginning of the host string:
            NSString* subExcluded = [excluded substringWithRange:range];
            searchRange = NSMakeRange(hostLocation, hostLength - hostLocation);
            NSRange matchRange = [host rangeOfString:subExcluded options:NSAnchoredSearch range:searchRange];
            if (matchRange.length == 0)
            {
                return NO;
            }
            hostLocation = range.length;
            excludedLocation = wildCardRange.location + 1;
        }
        else if (range.location + range.length >= excludedLength)
        {
            // This substring must be found at the end of the host string:
            NSString* subExcluded = [excluded substringWithRange:range];
            searchRange = NSMakeRange(hostLocation, hostLength - hostLocation);
            NSRange matchRange = [host rangeOfString:subExcluded options:NSAnchoredSearch | NSBackwardsSearch range:searchRange];
            if (matchRange.length == 0)
            {
                return NO;
            }
            excludedLocation = excludedLength;
        }
        else
        {
            // This substring must be found within the host string starting from the current search location:
            NSString* subExcluded = [excluded substringWithRange:range];
            searchRange = NSMakeRange(hostLocation, hostLength - hostLocation);
            NSRange matchRange = [host rangeOfString:subExcluded options:0 range:searchRange];
            if (matchRange.length == 0)
            {
                return NO;
            }
            hostLocation = matchRange.location + matchRange.length;
            excludedLocation = wildCardRange.location + 1;
        }
    }
    
    return YES;
}


// Implementation.
@implementation TelnetTerminal

@synthesize hostName;
@synthesize userName;
@synthesize columnCount;
@synthesize state;
@synthesize port;
@synthesize internetProtocol;
@synthesize proxyType;
@synthesize proxyHost;
@synthesize proxyPort;
@synthesize proxyPassword;
@synthesize proxyUser;
@synthesize proxyConnectCommand;
@synthesize proxyExclusion;
@synthesize proxyDnsLookup;
@synthesize proxyIncludeLocal;


-(void)setPassword:(NSString *)string
{
    [password release];
    password = string;
    [password retain];
}


-(BOOL)isProxyNeeded
{
    if (proxyType == telnetTerminalProxyNone)
    {
        return NO;
    }
    
    if (proxyIncludeLocal == NO)
    {
        if (isMatch(hostName, @"localhost") == YES || isMatch(hostName, @"127.*.*.*") == YES || isMatch(hostName, @"::1") == YES)
        {
            return NO;
        }
    }
    
    if (proxyExclusion.length > 0)
    {
        NSArray* hosts = [proxyExclusion componentsSeparatedByString:@","];
        for (int i = 0; i < hosts.count; i++)
        {
            if (isMatch(hostName, [hosts objectAtIndex:i]) == YES)
            {
                return NO;
            }
        }
    }
    
    return YES;
}


-(void)connect
{
    if (connection != nil)
    {
        if (state != telnetTerminalDisconnected)
        {
            return;
        }
    }
    state = telnetTerminalConnected;
    
    // Setup the main connection properties.
    connection = [[TelnetConnection alloc] init];
    [connection setEventDelegate:(id<TelnetConnectionEventDelegate>)self];
    [terminalView setConnection:connection];

    int family = PF_UNSPEC;
    if (internetProtocol == telnetTerminalIpv4)
    {
        family = PF_INET;
    }
    else if (internetProtocol == telnetTerminalIpv6)
    {
        family = PF_INET6;
    }
    [connection setHost:hostName port:port protocol:family];
    [connection setUser:userName];
    [connection setPassword:password];
    
    // Setup the proxy if required.
    if ([self isProxyNeeded] == YES)
    {
        if (proxyType == telnetTerminalProxySocks4)
        {
            ProxySocks4* proxy = [ProxySocks4 new];
            proxy.proxyHost = proxyHost;
            proxy.proxyPort = proxyPort;
            [connection setProxy:proxy];
            [proxy release];
        }
        else if (proxyType == telnetTerminalProxySocks5)
        {
            ProxySocks5* proxy = [ProxySocks5 new];
            proxy.proxyHost = proxyHost;
            proxy.proxyPort = proxyPort;
            proxy.proxyPassword = proxyPassword;
            proxy.proxyResolveHostAddress = (proxyDnsLookup == telnetTerminalDnsLookupProxyEnd ? NO : YES);
            [connection setProxy:proxy];
            [proxy release];
        }
        else if (proxyType == telnetTerminalProxyHttp)
        {
            ProxyHttp* proxy = [ProxyHttp new];
            proxy.proxyHost = proxyHost;
            proxy.proxyPort = proxyPort;
            proxy.proxyUser = proxyUser;
            proxy.proxyPassword = proxyPassword;
            proxy.proxyResolveHostAddress = (proxyDnsLookup == telnetTerminalDnsLookupLocal ? YES : NO);
            [connection setProxy:proxy];
            [proxy release];
        }
        else if (proxyType == telnetTerminalProxyTelnet)
        {
            ProxyTelnet* proxy = [ProxyTelnet new];
            proxy.proxyHost = proxyHost;
            proxy.proxyPort = proxyPort;
            proxy.proxyUser = proxyUser;
            proxy.proxyPassword = proxyPassword;
            proxy.connectCommand = proxyConnectCommand;
            proxy.proxyResolveHostAddress = (proxyDnsLookup == telnetTerminalDnsLookupLocal ? YES : NO);
            [connection setProxy:proxy];
            [proxy release];
        }
    }
    
    // Setup the terminal.
    [terminalView setColumnCount:columnCount];
    [terminalView setRowCountForHeight:self.contentSize.height];
    [terminalView initScreen];
    
    [connection startConnection];
}


-(void)disconnect
{
    if (connection != nil)
    {
        if (state == telnetTerminalDisconnected)
        {
            return;
        }
        state = telnetTerminalDisconnected;
        [connection endConnection];
    }
}


-(void)viewDidEndLiveResize
{
    [terminalView setRowCountForHeight:self.contentSize.height];
}


-(void)autoSetHorizontalScroller
{
    int width = self.contentSize.width;
    int containerWidth = ((VT100TerminalView*)terminalView).textContainer.containerSize.width;
    if (width < containerWidth)
    {
        [self setHasHorizontalScroller:YES];
    }
    else
    {
        [self setHasHorizontalScroller:NO];
    }
}


-(void)setFrame:(NSRect)frame
{
    [super setFrame:frame];
    
    [self autoSetHorizontalScroller];
}


-(void)setFrameSize:(NSSize)newSize
{
    [super setFrameSize:newSize];
    
    [self autoSetHorizontalScroller];
}


-(void)setEventDelegate:(id)delegate
{
    [eventDelegate release];
    eventDelegate = delegate;
    [eventDelegate retain];
}


-(void)signalError:(int)code
{
    switch (code)
    {
        case tceConnected:
        {
            [terminalView setCursorVisible:YES];
            if ([eventDelegate respondsToSelector:@selector(connected)])
            {
                [eventDelegate connected];
            }
            break;
        }
            
        case tceDisconnected:
        {
            state = telnetTerminalDisconnected;
            [terminalView setCursorVisible:NO];
            if ([eventDelegate respondsToSelector:@selector(disconnected)])
            {
                [eventDelegate disconnected];
            }
            connection = nil;
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


-(void)initSubclassMembers
{
    state = telnetTerminalDisconnected;
    port = 23;
    
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
    
    [self setDocumentView:terminalView];
}


-(instancetype)initWithFrame:(NSRect)frameRect
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


-(instancetype)init
{
    return [self initWithFrame:NSMakeRect(0, 0, 0, 0)];
}


-(void)dealloc
{
    [password release];
    [hostName release];
    [userName release];
    [proxyHost release];
    [proxyUser release];
    [proxyPassword release];
    [proxyConnectCommand release];
    [proxyExclusion release];
    [eventDelegate release];
    
    [super dealloc];
}


@end
