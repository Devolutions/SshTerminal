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
    _terminal.userName = @"david";
    _terminal.hostName = @"192.168.7.60";
    [_terminal setPassword:@"123456"];
    _terminal.columnCount = 80;
    [_terminal connect];
    [_connectButton setEnabled:NO];
}


- (IBAction)disconnect:(id)sender
{
    [_terminal disconnect];
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


-(void)error:(int)code
{
    NSString* errorString = [NSString stringWithFormat:@"Error: %d", code];
    [_errorText setStringValue:errorString];
}


@end
