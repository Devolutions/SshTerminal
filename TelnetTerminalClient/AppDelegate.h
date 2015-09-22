//
//  AppDelegate.h
//  TelnetTerminalClient
//
//  Created by Denis Vincent on 2015-07-22.
//  Copyright (c) 2015 Denis Vincent. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "TelnetTerminal.h"

@interface AppDelegate : NSObject <NSApplicationDelegate>
{
    IBOutlet TelnetTerminal *terminal;
    IBOutlet NSButton *connectButton;
    IBOutlet NSTextField *statusText;
    IBOutlet NSButton *disconnectButton;
    IBOutlet NSTextField *errorText;
    IBOutlet NSWindow *window;
    BOOL resume;
}

@property (weak) IBOutlet TelnetTerminal *terminal;
@property (weak) IBOutlet NSButton *connectButton;
@property (weak) IBOutlet NSTextField *statusText;
@property (weak) IBOutlet NSButton *disconnectButton;
@property (weak) IBOutlet NSTextField *errorText;
@property (weak) IBOutlet NSWindow *window;

@end

