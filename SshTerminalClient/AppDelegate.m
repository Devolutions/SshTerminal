//
//  AppDelegate.m
//  LibSshTest
//
//  Created by Denis Vincent on 2015-06-03.
//  Copyright (c) 2015 Denis Vincent. All rights reserved.
//

#import "AppDelegate.h"
#import "SshConnection.h"


SshConnection* sshConnection = NULL;

@implementation AppDelegate

@synthesize terminal;
@synthesize errorText;
@synthesize statusText;
@synthesize connectButton;
@synthesize disconnectButton;
@synthesize window;


- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    resume = NO;
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
#define TEST_SERVER 4
        
#if (TEST_SERVER == 0)
        terminal.userName = @"david";
        terminal.hostName = @"192.168.7.60";
        [terminal setPassword:@"123456"];
        //terminal.x11Forwarding = YES;
        //terminal.internetProtocol = sshTerminalIpv6;
#elif (TEST_SERVER == 1)
        terminal.userName = @"dvincent";
        terminal.hostName = @"192.168.4.1";
        [terminal setPassword:@"Price2011"];
        [terminal clearAllTunnels];
#elif (TEST_SERVER == 2)
        terminal.userName = @"dvincent";
        terminal.hostName = @"192.168.4.1";
        terminal.keyFilePath = @"~/dvincentkey";
        [terminal setKeyFilePassword:@"123456"];
#elif (TEST_SERVER == 3)
        terminal.userName = @"dvincent";
        terminal.hostName = @"192.168.4.1";
        [terminal setPassword:@"Price2011"];
        [terminal clearAllTunnels];
        [terminal addForwardTunnelWithPort:15500 onHost:@"::1" andRemotePort:15500 onRemoteHost:@"localhost"];
        //terminal.internetProtocol = sshTerminalIpv6;
        //[terminal addReverseTunnelWithPort:15601 onHost:@"localhost" andRemotePort:15600 onRemoteHost:@"localhost"];
#elif (TEST_SERVER == 4)
        terminal.userName = @"david";
        terminal.hostName = @"192.168.1.141";
        [terminal setPassword:@"123456"];
#endif
        terminal.columnCount = 80;
        [terminal connect];
        [statusText setStringValue:@"Connecting"];
        [connectButton setEnabled:NO];
    }
    else   // Resume.
    {
        [terminal resumeAndRememberServer];
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
    //[terminal send:@"xclock\r\n"];
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
