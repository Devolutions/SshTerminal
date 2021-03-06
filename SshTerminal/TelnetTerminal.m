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
    password = [string copy];
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


-(void)setDefaultBackgroundRed:(UInt8)r green:(UInt8)g blue:(UInt8)b
{
	[defaultBackground release];
	defaultBackground = [NSColor colorWithRed:(float)r / 255.0 green:(float)g / 255.0 blue:(float)b / 255.0 alpha:1.0];
	[defaultBackground retain];
}


-(void)setDefaultForegroundRed:(UInt8)r green:(UInt8)g blue:(UInt8)b
{
	[defaultForeground release];
	defaultForeground = [NSColor colorWithRed:(float)r / 255.0 green:(float)g / 255.0 blue:(float)b / 255.0 alpha:1.0];
	[defaultForeground retain];
}


-(void)setCursorBackgroundRed:(UInt8)r green:(UInt8)g blue:(UInt8)b
{
	[cursorBackground release];
	cursorBackground = [NSColor colorWithRed:(float)r / 255.0 green:(float)g / 255.0 blue:(float)b / 255.0 alpha:1.0];
	[cursorBackground retain];
}


-(void)setCursorForegroundRed:(UInt8)r green:(UInt8)g blue:(UInt8)b
{
	[cursorForeground release];
	cursorForeground = [NSColor colorWithRed:(float)r / 255.0 green:(float)g / 255.0 blue:(float)b / 255.0 alpha:1.0];
	[cursorForeground retain];
}


-(void)setColor:(int)index red:(UInt8)r green:(UInt8)g blue:(UInt8)b
{
	[colors[index] release];
	colors[index] = [NSColor colorWithRed:(float)r / 255.0 green:(float)g / 255.0 blue:(float)b / 255.0 alpha:1.0];
	[colors[index] retain];
}


-(void)syntaxColoringAddOrUpdateItem:(NSString*)keyword itemBackColor:(int)backColor itemTextColor:(int)textColor itemIsCompleteWord:(BOOL)isCompleteWord itemIsCaseSensitive:(BOOL)isCaseSensitive itemIsUnderlined:(BOOL)isUnderlined
{
	NSEnumerator* i = [syntaxColoringItems objectEnumerator];
	SyntaxColoringItem* item;
	BOOL itemDoesntExist = true;
	while ((item = [i nextObject]))
	{
		if ([item.keyword compare:keyword] == NSOrderedSame)
		{
			item.keyword = keyword;
			item.keywordLen = (int)[keyword length];
			item.backColor = backColor;
			item.textColor = textColor;
			item.isCompleteWord = isCompleteWord;
			item.isCaseSensitive = isCaseSensitive;
			item.isUnderlined = isUnderlined;
			item.isEnabled = true;
			itemDoesntExist = false;
			break;
		}
	}
	
	if (itemDoesntExist)
	{
		SyntaxColoringItem* it = [[SyntaxColoringItem alloc] init];
		it.keyword = keyword;
		it.keywordLen = (int)[keyword length];
		it.backColor = backColor;
		it.textColor = textColor;
		it.isCompleteWord = isCompleteWord;
		it.isCaseSensitive = isCaseSensitive;
		it.isUnderlined = isUnderlined;
		it.isEnabled = true;
		[syntaxColoringItems addObject:it];
		[it release];
	}
	
	syntaxColoringChangeMade = true;
}


-(void)syntaxColoringDeleteItem:(NSString*)keyword
{
	NSEnumerator *i = [syntaxColoringItems objectEnumerator];
	SyntaxColoringItem* item;
	while ((item = [i nextObject]))
	{
		if ([item.keyword compare:keyword] == NSOrderedSame)
		{
			[syntaxColoringItems removeObject:item];
			syntaxColoringChangeMade = true;
			break;
		}
	}
}


-(void)syntaxColoringEnableItem:(NSString*)keyword
{
	NSEnumerator *i = [syntaxColoringItems objectEnumerator];
	SyntaxColoringItem* item;
	while ((item = [i nextObject]))
	{
		if ([item.keyword compare:keyword] == NSOrderedSame)
		{
			item.isEnabled = true;
			syntaxColoringChangeMade = true;
			break;
		}
	}
}


-(void)syntaxColoringDisableItem:(NSString*)keyword
{
	NSEnumerator *i = [syntaxColoringItems objectEnumerator];
	SyntaxColoringItem* item;
	while ((item = [i nextObject]))
	{
		if ([item.keyword compare:keyword] == NSOrderedSame)
		{
			item.isEnabled = false;
			syntaxColoringChangeMade = true;
			break;
		}
	}
}


-(void)syntaxColoringDeleteAllItems
{
	[syntaxColoringItems removeAllObjects];
	syntaxColoringChangeMade = true;
}


-(void)syntaxColoringEnableAllItems
{
	NSEnumerator *i = [syntaxColoringItems objectEnumerator];
	SyntaxColoringItem* item;
	while ((item = [i nextObject]))
	{
		item.isEnabled = true;
	}
	
	syntaxColoringChangeMade = true;
}


-(void)syntaxColoringDisableAllItems
{
	NSEnumerator *i = [syntaxColoringItems objectEnumerator];
	SyntaxColoringItem* item;
	while ((item = [i nextObject]))
	{
		item.isEnabled = false;
	}
	
	syntaxColoringChangeMade = true;
}


-(void)syntaxColoringApplyChanges
{
	if (syntaxColoringScreenInitiated)
	{
		[terminalView.screen applyChanges];
	}
}


-(void)connect
{
    if (state != telnetTerminalDisconnected)
    {
        return;
    }
    state = telnetTerminalConnected;
    
    // Setup the main connection properties.
    [connection release];
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
    
	// Setup terminal colors.
	[terminalView.screen setDefaultBackgroundColor:defaultBackground foregroundColor:defaultForeground];
	[terminalView.screen setCursorBackgroundColor:cursorBackground foregroundColor:cursorForeground];
	for (int i = 0; i < 8; i++)
	{
		[terminalView.screen setColor:colors[i * 2] at:i];
		[terminalView.screen setColor:colors[i * 2 + 1] at:i + 8];
	}
	
    [terminalView initScreen];
    
	// Setup initial syntax coloring.
	if (syntaxColoringScreenInitiated == false)
	{
		terminalView.screen.syntaxColoringItems = syntaxColoringItems;
		terminalView.screen.syntaxColoringChangeMade = &syntaxColoringChangeMade;
		syntaxColoringScreenInitiated = true;
		[self syntaxColoringApplyChanges];
	}
	
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

-(void)send:(NSString *)string
{
    if (connection != nil)
    {
        if (state != telnetTerminalConnected)
        {
            return;
        }
        const char* utf8String = [string UTF8String];
        [connection writeFrom:(const UInt8*)utf8String length:(int)strlen(utf8String)];
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


-(void)setFontWithName:(NSString *)fontName size:(CGFloat)fontSize
{
	[terminalView.screen setFontWithname:fontName size:fontSize];
	NSSize size = [self contentSize];
	[terminalView setTerminalSize:size];
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
    
	defaultBackground = [NSColor blackColor];
	[defaultBackground retain];
	defaultForeground = [NSColor whiteColor];
	[defaultForeground retain];
	cursorBackground = [NSColor whiteColor];
	[cursorBackground retain];
	cursorForeground = [NSColor blackColor];
	[cursorForeground retain];
	colors[0] = [NSColor blackColor];
	[colors[0] retain];
	colors[1] = [NSColor darkGrayColor];
	[colors[1] retain];
	colors[2] = [NSColor redColor];
	[colors[2] retain];
	colors[3] = [NSColor colorWithRed:1.0F green:0.333F blue:0.333F alpha:1.0F];
	[colors[3] retain];
	colors[4] = [NSColor greenColor];
	[colors[4] retain];
	colors[5] = [NSColor colorWithRed:0.333F green:1.0F blue:0.333F alpha:1.0F];
	[colors[5] retain];
	colors[6] = [NSColor colorWithRed:0.733F green:0.733F blue:0.0F alpha:1.0F];
	[colors[6] retain];
	colors[7] = [NSColor colorWithRed:1.0F green:1.0F blue:0.733F alpha:1.0F];
	[colors[7] retain];
	colors[8] = [NSColor colorWithRed:0.0F green:0.0F blue:0.733F alpha:1.0F];
	[colors[8] retain];
	colors[9] = [NSColor colorWithRed:0.733F green:0.733F blue:1.0F alpha:1.0F];
	[colors[9] retain];
	colors[10] = [NSColor colorWithRed:0.733F green:0.0F blue:0.733F alpha:1.0F];
	[colors[10] retain];
	colors[11] = [NSColor colorWithRed:1.0F green:0.333F blue:1.0F alpha:1.0F];
	[colors[11] retain];
	colors[12] = [NSColor colorWithRed:0.0F green:0.733F blue:0.733F alpha:1.0F];
	[colors[12] retain];
	colors[13] = [NSColor colorWithRed:0.733F green:1.0F blue:1.0F alpha:1.0F];
	[colors[13] retain];
	colors[14] = [NSColor colorWithRed:0.733F green:0.733F blue:0.733F alpha:1.0F];
	[colors[14] retain];
	colors[15] = [NSColor whiteColor];
	[colors[15] retain];
	
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
