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


- (void)changeFont:(id)sender
{
	NSFont *oldFont = [sender selectedFont];
	NSFont *newFont = [sender convertFont:oldFont];
	[terminal setFontWithName:[newFont fontName] size:[newFont pointSize]];
	printf("New font: %s\r\n", [[newFont fontName] UTF8String]);
}


- (IBAction)connect:(id)sender
{
    if (resume == NO)
    {
#define TEST_SERVER 4
        
		/*NSFont* font = [NSFont userFixedPitchFontOfSize:0];
		NSFontManager* manager = [NSFontManager sharedFontManager];
		[manager setSelectedFont:font isMultiple:NO];
		[manager setTarget:self];
		[manager orderFrontFontPanel:self];*/
		
        [terminal clearAllTunnels];
		//terminal.verbose = YES;
		//terminal.verbosityLevel = 1;
		terminal.keepAliveTime = 5;
		
#if (TEST_SERVER == 0)
        terminal.hostName = @"192.168.7.60";
        terminal.port = 2220;
        terminal.userName = @"david";
        [terminal setPassword:@"123456"];
		terminal.jumpHostName = @"macmini2";
		terminal.jumpPort = 22;
		terminal.jumpUserName = @"david";
		[terminal setJumpPassword:@"123456"];
        //terminal.hostName = @"192.168.7.60";
        //terminal.agentForwarding = YES;
        //terminal.keyFilePath = @"~/Encrypted.ppk";
        //terminal.keyFilePath = @"~/.ssh/dvincent-dsa";
        //[terminal setKeyFilePassword:@"qwerty"];
		//terminal.agentForwarding = YES;
        //terminal.x11Forwarding = YES;
        //terminal.internetProtocol = sshTerminalIpv6;
#elif (TEST_SERVER == 1)
        terminal.hostName = @"192.168.7.62";
		terminal.port = 2222;
        terminal.userName = @"test";
        [terminal setPassword:@"123456"];
		//terminal.keyFilePath = @"~/.ssh/dvincent-rsa";
		//[terminal setKeyFilePassword:@"qwerty"];
		terminal.agentForwarding = YES;
#elif (TEST_SERVER == 2)
        terminal.userName = @"dvincent";
        terminal.hostName = @"192.168.4.1";
        terminal.keyFilePath = @"~/dvincentkey";
        [terminal setKeyFilePassword:@"123456"];
#elif (TEST_SERVER == 3)
        terminal.userName = @"parallels";
        terminal.hostName = @"192.168.4.4";
        [terminal setPassword:@"Price2011"];
        //terminal.internetProtocol = sshTerminalIpv6;
        //[terminal addReverseTunnelWithPort:15601 onHost:@"localhost" andRemotePort:15600 onRemoteHost:@"localhost"];
#elif (TEST_SERVER == 4)
        terminal.hostName = @"macmini2";
        terminal.port = 22;
        terminal.userName = @"david";
        [terminal setPassword:@"123456"];
        //[terminal addForwardTunnelWithPort:1080 onHost:@"localhost" andRemotePort:23 onRemoteHost:@"VDEVOSRV-TST"];
        //[terminal addForwardTunnelWithPort:3389 onHost:@"0.0.0.0" andRemotePort:3389 onRemoteHost:@"192.168.7.203"];
#elif (TEST_SERVER == 5)
		terminal.hostName = @"192.168.1.217";
		terminal.port = 2222;
		terminal.userName = @"test";
		[terminal setPassword:@"123456"];
		//[terminal addForwardTunnelWithPort:1080 onHost:@"localhost" andRemotePort:2220 onRemoteHost:@"192.168.7.60"];
		//terminal.keepAliveTime = 1;
		//terminal.internetProtocol = sshTerminalIpv6;
		//terminal.useAgent = YES;
		//terminal.verbose = YES;
		//terminal.verbosityLevel = 1;
		//[terminal addForwardTunnelWithPort:1080 onHost:@"localhost" andRemotePort:23 onRemoteHost:@"VDEVOSRV-TST"];
		//[terminal addForwardTunnelWithPort:3389 onHost:@"0.0.0.0" andRemotePort:3389 onRemoteHost:@"192.168.7.203"];
#elif (TEST_SERVER == 6)
		terminal.hostName = @"do02.flj.net";
		terminal.port = 22;
		terminal.userName = @"test";
		[terminal setPassword:@"123456"];
		terminal.verbose = YES;
		terminal.verbosityLevel = 1;
#endif
        //terminal.verbose = YES;
		
		// SyntaxColoring specific.
		//[terminal syntaxColoringAddOrUpdateItem:@"test" itemBackColor:0 itemTextColor:6 itemIsCompleteWord:false itemIsCaseSensitive:false itemIsUnderlined:false];
		//[terminal syntaxColoringAddOrUpdateItem:@"welcome" itemBackColor:0 itemTextColor:7 itemIsCompleteWord:true itemIsCaseSensitive:false itemIsUnderlined:true];
		
		[terminal setDefaultBackgroundRed:255 green:255 blue:255];
		[terminal setDefaultForegroundRed:0 green:0 blue:0];
		[terminal setCursorBackgroundRed:255 green:0 blue:0];
		[terminal setCursorForegroundRed:0 green:255 blue:255];
		
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
