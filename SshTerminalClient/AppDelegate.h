//
//  AppDelegate.h
//  LibSshTest
//
//  Created by Denis Vincent on 2015-06-03.
//  Copyright (c) 2015 Denis Vincent. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "SshTerminal.h"

@interface AppDelegate : NSObject <NSApplicationDelegate, SshTerminalEvent>
{
    NSTextStorage* storage;
    BOOL resume;
}

@property (weak) IBOutlet NSWindow *window;
@property (weak) IBOutlet NSTextField *statusText;
@property (weak) IBOutlet NSButton *connectButton;
@property (weak) IBOutlet NSButton *disconnectButton;
@property (weak) IBOutlet NSTextField *errorText;

@property (unsafe_unretained) IBOutlet SshTerminal *terminal;

- (IBAction)connect:(id)sender;
- (IBAction)disconnect:(id)sender;


@end

