//
//  AppDelegate.m
//  TelnetTerminalClient
//
//  Created by Denis Vincent on 2015-07-22.
//  Copyright (c) 2015 Denis Vincent. All rights reserved.
//

#import "AppDelegate.h"

@interface AppDelegate () <TelnetTerminalEvent>


@end

@implementation AppDelegate

@synthesize terminal;
@synthesize connectButton;
@synthesize statusText;
@synthesize disconnectButton;
@synthesize errorText;
@synthesize window;

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    [terminal setEventDelegate:self];
}


- (void)applicationWillTerminate:(NSNotification *)aNotification
{
    terminal = NULL;
}


- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)theApplication
{
    return YES;
}


- (IBAction)connect:(id)sender
{
    if (resume == NO)
    {
#define TEST_SERVER 1
        
#if (TEST_SERVER == 0)
        terminal.userName = @"devolutions\\test";
        terminal.hostName = @"VDEVOSRV-TST.devolutions.loc";
        [terminal setPassword:@"Price2011"];
#elif (TEST_SERVER == 1)
        terminal.proxyPort = 8080;
        terminal.proxyHost = @"127.0.0.1";
        terminal.proxyType = telnetTerminalProxyHttp;
        terminal.proxyDnsLookup = telnetTerminalDnsLookupLocal;
        terminal.userName = @"devolutions\\test";
        terminal.hostName = @"VDEVOSRV-TST.devolutions.loc";
        [terminal setPassword:@"Price2011"];
#endif
        terminal.columnCount = 80;
        [terminal connect];
        [statusText setStringValue:@"Connecting"];
        [connectButton setEnabled:NO];
    }
    else   // Resume.
    {
        [connectButton setTitle:@"Connect"];
        [connectButton setEnabled:NO];
        resume = NO;
    }
}


- (IBAction)disconnect:(id)sender
{
    [terminal disconnect];
    [connectButton setTitle:@"Connect"];
    [connectButton setEnabled:NO];
    resume = NO;
}


-(void)connected
{
    [statusText setStringValue:@"Connected"];
    [disconnectButton setEnabled:YES];
}


-(void)disconnected
{
    [statusText setStringValue:@"Disconnected"];
    [disconnectButton setEnabled:NO];
    [connectButton setEnabled:YES];
}


-(void)serverMismatch:(NSString *)fingerPrint
{
    [errorText setStringValue:fingerPrint];
    [connectButton setTitle:@"Resume"];
    [connectButton setEnabled:YES];
    [disconnectButton setEnabled:YES];
    resume = YES;
}


-(void)error:(int)code
{
    NSString* errorString = [NSString stringWithFormat:@"Error: %d", code];
    [errorText setStringValue:errorString];
}


@end
