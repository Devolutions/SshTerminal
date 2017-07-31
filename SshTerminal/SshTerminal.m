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
@synthesize jumpHostName;
@synthesize jumpUserName;
@synthesize jumpKeyFilePath;
@synthesize columnCount;
@synthesize state;
@synthesize port;
@synthesize jumpPort;
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


-(void)setJumpPassword:(NSString *)string
{
	jumpPassword = [string copy];
}


-(void)setJumpKeyFilePassword:(NSString *)string
{
	jumpKeyFilePassword = [string copy];
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


-(void)connect
{
    if (state != sshTerminalDisconnected)
    {
        return;
    }
    state = sshTerminalConnected;
    
	int family = PF_UNSPEC;
	if (internetProtocol == sshTerminalIpv4)
	{
		family = PF_INET;
	}
	else if (internetProtocol == sshTerminalIpv6)
	{
		family = PF_INET6;
	}

	[connection release];
	connection = [[SshConnection alloc] init];
	[connection setEventDelegate:self];
	[terminalView setConnection:connection];
	
	[jump release];
	if (jumpHostName == nil || jumpHostName.length == 0)
	{
		jump = nil;
	}
	else
	{
		jump = [[SshConnection alloc] initWithConnection:connection];
		[jump setEventDelegate:self];
		[jump setHost:jumpHostName port:jumpPort protocol:family];
		[jump setUser:jumpUserName];
		[jump setKeyFilePath:[jumpKeyFilePath stringByExpandingTildeInPath] withPassword:jumpKeyFilePassword];
		[jump setPassword:jumpPassword];
		[jump setVerbose:verbose withLevel:verbosityLevel];

		[jump addForwardTunnelPort:0 host:@"127.0.0.1" remotePort:port remoteHost:hostName];
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
	
	if (jump != nil)
	{
		[jump startConnection];
	}
	else
	{
		[connection startConnection];
	}
}


-(void)resume
{
	if (state != sshTerminalPaused)
	{
		return;
	}
	
	if (paused == jump)
	{
		[jump resume:YES andSaveHost:NO];
	}
    else if (paused == connection)
    {
        state = sshTerminalConnected;
        [connection resume:YES andSaveHost:NO];
    }
	paused = nil;
}


-(void)resumeAndRememberServer
{
	if (state != sshTerminalPaused)
	{
		return;
	}

	if (paused == jump)
	{
		[jump resume:YES andSaveHost:YES];
	}
	else if (paused == connection)
	{
		state = sshTerminalConnected;
		[connection resume:YES andSaveHost:YES];
	}
	paused = nil;
}


-(void)disconnect
{
	if (state == sshTerminalDisconnected)
	{
		return;
	}
	
	if (state == sshTerminalPaused)
	{
		if (paused == jump)
		{
			[jump endConnection];
		}
		paused = nil;
	}
	
    if (connection != nil)
    {
        [connection endConnection];
    }
	
	state = sshTerminalDisconnected;
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


-(void)signalDisconnected
{
	[connection release];
	connection = nil;
	[jump release];
	jump = nil;
	
	if ([eventDelegate respondsToSelector:@selector(disconnected)])
	{
		[eventDelegate disconnected];
	}
	
	// Get ready for next session.
	isConnectionClosed = NO;
	isJumpClosed = NO;
}


-(void)callbackFromConnection:(id)caller withCode:(int)code
{
	// This method is called through a dispatch_async on the main queue.
    switch (code)
    {
        case CONNECTED:
        {
			if (caller == connection)
			{
				if (tunnels.count == 0)
				{
					[terminalView setCursorVisible:YES];
				}
				if ([eventDelegate respondsToSelector:@selector(connected)])
				{
					[eventDelegate connected];
				}
			}
			else
			{
				UInt16 tunnelPort = [jump jumpPort];
				if (tunnelPort == 0)
				{
					[jump endConnection];
				}
				else
				{
					[connection setSocketHost:@"127.0.0.1" port:tunnelPort];
					[connection startConnection];
				}
			}
            break;
        }
            
        case DISCONNECTED:
        {
			[terminalView setCursorVisible:NO];
			if (caller == connection)
			{
				if (jump == nil)
				{
					state = sshTerminalDisconnected;
					[self signalDisconnected];
				}
				else
				{
					if (isJumpClosed)
					{
						state = sshTerminalDisconnected;
						[self signalDisconnected];
					}
					else
					{
						isConnectionClosed = YES;
						[jump endConnection];
					}
				}
			}
			else
			{
				if (isConnectionClosed)
				{
					state = sshTerminalDisconnected;
					[self signalDisconnected];
				}
				else
				{
					isJumpClosed = YES;
					[connection endConnection];
				}
			}
            break;
        }
            
        case SERVER_KEY_CHANGED:
        case SERVER_KEY_FOUND_OTHER:
        case SERVER_NOT_KNOWN:
        {
            state = sshTerminalPaused;
			paused = caller;
            if ([eventDelegate respondsToSelector:@selector(serverMismatch:)])
            {
                NSString* fingerPrint = [paused fingerPrint];
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


-(void)initSubclassMembers
{
    state = sshTerminalDisconnected;
    port = 22;
    tunnels = [NSMutableArray new];
	
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
    [terminalView setEditable:YES];
    [self adjustTerminalSize];
    
    [self setDocumentView:terminalView];
	
	syntaxColoringItems = [NSMutableArray new];
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


- (void)dealloc
{
	[defaultBackground release];
	[defaultForeground release];
	for (int i = 0; i < 16; i++)
	{
		[colors[i] release];
	}
	[syntaxColoringItems release];
	[x11AuthorityFile release];
	[x11Authentication release];
	[keyFilePath release];
	[hostName release];
	[userName release];
	[x11Display release];
	[super dealloc];
}


@end
