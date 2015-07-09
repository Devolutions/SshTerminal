//
//  SshTerminal.m
//  LibSshTest
//
//  Created by Denis Vincent on 2015-06-05.
//  Copyright (c) 2015 Denis Vincent. All rights reserved.
//

#import "SshTerminal.h"
#import "SshTerminalView.h"
#import "SshConnection.h"


@interface SshTerminal () <SshConnectionEventDelegate>
{
    SshTerminalView* terminalView;
    SshConnection* connection;
}

@end


@implementation SshTerminal

@synthesize hostName;
@synthesize userName;
@synthesize keyFilePath;
@synthesize columnCount;
@synthesize state;


-(void)setPassword:(NSString *)string
{
    password = string;
}


-(void)setKeyFilePassword:(NSString *)string
{
    keyFilePassword = string;
}


-(void)connect
{
    if (connection != nil)
    {
        if (state != sshTerminalDisconnected)
        {
            return;
        }
    }
    state = sshTerminalConnected;
    
    connection = [[SshConnection alloc] init];
    [connection setEventDelegate:self];
    [terminalView setConnection:connection];

    [connection setHost:[hostName UTF8String]];
    [connection setPort:port];
    [connection setUser:[userName UTF8String]];
    [connection setKeyFilePath:[[keyFilePath stringByExpandingTildeInPath] UTF8String] withPassword:[keyFilePassword UTF8String]];
    [connection setPassword:[password UTF8String]];
    [terminalView setColumnCount:columnCount];
    [terminalView setRowCountForHeight:self.contentSize.height];
    [terminalView initScreen];
    
    [connection connect];
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


-(void)viewDidEndLiveResize
{
    [terminalView setRowCountForHeight:self.contentSize.height];
}


-(void)autoSetHorizontalScroller
{
    int width = self.contentSize.width;
    int containerWidth = ((SshTerminalView*)terminalView).textContainer.containerSize.width;
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
        case CONNECTED:
        {
            [terminalView setCursorVisible:YES];
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


-(void)initSubclassMembers
{
    state = sshTerminalDisconnected;
    port = 22;
    
    [self setAutoresizesSubviews:YES];
    [self setHasVerticalScroller:YES];
    [self setHasHorizontalScroller:NO];
    [self setAutoresizesSubviews:YES];
    
    NSClipView* clip = [[NSClipView alloc] init];
    [self setContentView:clip];

    NSRect rect;
    rect.origin = NSMakePoint(0, 0);
    rect.size = self.contentSize;

    terminalView = [[SshTerminalView alloc] initWithFrame:rect];
    [terminalView setEditable:NO];
    
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


@end
