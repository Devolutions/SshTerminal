//
//  AppDelegate.m
//  TelnetTerminalClient
//
//  Created by Denis Vincent on 2015-07-22.
//  Copyright (c) 2015 Denis Vincent. All rights reserved.
//

#import "AppDelegate.h"
#import "TelnetTerminal.h"

@interface AppDelegate () <TelnetTerminalEvent>
{
    BOOL resume;
}

@property (weak) IBOutlet NSWindow *window;
@property (weak) IBOutlet TelnetTerminal *terminal;
@property (weak) IBOutlet NSButton *connectButton;
@property (weak) IBOutlet NSButton *disconnectButton;
@property (weak) IBOutlet NSTextField *statusText;
@property (weak) IBOutlet NSTextField *errorText;

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    [_terminal setEventDelegate:self];
}


- (void)applicationWillTerminate:(NSNotification *)aNotification
{
    _terminal = NULL;
}


- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)theApplication
{
    return YES;
}


- (IBAction)connect:(id)sender
{
    if (resume == NO)
    {
#define TEST_SERVER 0
        
#if (TEST_SERVER == 0)
        _terminal.userName = @"devolutions\\test";
        _terminal.hostName = @"VDEVOSRV-TST.devolutions.loc";
        [_terminal setPassword:@"Price2011"];
#endif
        _terminal.columnCount = 80;
        [_terminal connect];
        [_statusText setStringValue:@"Connecting"];
        [_connectButton setEnabled:NO];
    }
    else   // Resume.
    {
        [_connectButton setTitle:@"Connect"];
        [_connectButton setEnabled:NO];
        resume = NO;
    }
}


- (IBAction)disconnect:(id)sender
{
    [_terminal disconnect];
    [_connectButton setTitle:@"Connect"];
    [_connectButton setEnabled:NO];
    resume = NO;
}


-(void)connected
{
    [_statusText setStringValue:@"Connected"];
    [_disconnectButton setEnabled:YES];
}


-(void)disconnected
{
    [_statusText setStringValue:@"Disconnected"];
    [_disconnectButton setEnabled:NO];
    [_connectButton setEnabled:YES];
}


-(void)serverMismatch:(NSString *)fingerPrint
{
    [_errorText setStringValue:fingerPrint];
    [_connectButton setTitle:@"Resume"];
    [_connectButton setEnabled:YES];
    [_disconnectButton setEnabled:YES];
    resume = YES;
}


-(void)error:(int)code
{
    NSString* errorString = [NSString stringWithFormat:@"Error: %d", code];
    [_errorText setStringValue:errorString];
}


@end
