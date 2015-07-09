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

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    resume = NO;
    [_terminal setEventDelegate:self];
}


- (void)applicationWillTerminate:(NSNotification *)aNotification
{
    // Insert code here to tear down your application
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
        _terminal.userName = @"david";
        _terminal.hostName = @"192.168.7.60";
        [_terminal setPassword:@"123456"];
#elif (TEST_SERVER == 1)
        _terminal.userName = @"dvincent";
        _terminal.hostName = @"192.168.4.1";
        [_terminal setPassword:@"Price2011"];
#elif (TEST_SERVER == 2)
        _terminal.userName = @"dvincent";
        _terminal.hostName = @"192.168.4.1";
        _terminal.keyFilePath = @"~/dvincentkey";
        [_terminal setKeyFilePassword:@"123456"];
#endif
        _terminal.columnCount = 80;
        [_terminal connect];
        [_statusText setStringValue:@"Connecting"];
        [_connectButton setEnabled:NO];
    }
    else   // Resume.
    {
        [_terminal resumeAndRememberServer];
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
