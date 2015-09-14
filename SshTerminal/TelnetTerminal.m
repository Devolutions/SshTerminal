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


// Private extension.
@interface TelnetTerminal () <TelnetConnectionEventDelegate>

@end


// Implementation.
@implementation TelnetTerminal

@synthesize hostName;
@synthesize userName;
@synthesize columnCount;
@synthesize state;
@synthesize port;


-(void)setPassword:(NSString *)string
{
    password = [string copy];
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
    
    connection = [[TelnetConnection alloc] init];
    [connection setEventDelegate:self];
    [terminalView setConnection:connection];

    [connection setHost:hostName];
    [connection setPort:port];
    [connection setUser:userName];
    [connection setPassword:password];
    
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
    eventDelegate = delegate;
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


@end
