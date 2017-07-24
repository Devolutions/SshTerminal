//
//  SshTerminal.h
//  LibSshTest
//
//  Created by Denis Vincent on 2015-06-03.
//  Copyright (c) 2015 Denis Vincent. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "VT100Connection.h"
#import "VT100ScreenBuffer.h"


@interface VT100TerminalView : NSTextView
{
    id<VT100Connection> connection;
    VT100ScreenBuffer* screen;

    int columnCount;
    int rowCount;
	int markRange;
    
    BOOL isCursorVisible;
	BOOL isKeyIntercepted;
}

-(VT100ScreenBuffer*)screen;

-(void)initScreen;

-(void)setConnection:(id<VT100Connection>)newConnection;
-(void)setCursorVisible:(BOOL)visible;
-(BOOL)cursorVisible;
-(void)setTerminalSize:(NSSize)newSize;


@end
