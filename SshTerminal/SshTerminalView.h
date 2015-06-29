//
//  SshTerminal.h
//  LibSshTest
//
//  Created by Denis Vincent on 2015-06-03.
//  Copyright (c) 2015 Denis Vincent. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "SshConnection.h"

#define TERMINAL_BUFFER_SIZE 1024

typedef union
{
    UInt32 all;
    struct
    {
        UInt16 flags;
        UInt8 backColor;
        UInt8 textColor;
    };
} TerminalAttribute;


@interface SshTerminalView : NSTextView
{
    SshConnection* connection;
    NSTextStorage* storage;
    UInt8 inBuffer[TERMINAL_BUFFER_SIZE];
    UInt32 inIndex;
    
    NSFont* normalFont;
    NSFont* boldFont;
    NSColor* backColors[9];
    NSColor* textColors[9];
    BOOL isCursorVisible;
    
    NSMutableParagraphStyle* paragraphStyle;
    NSDictionary* newLineAttributes;
    NSAttributedString* blankLine;
    NSAttributedString* blankChar;
    NSAttributedString* lineFeed;
    NSMutableAttributedString* insert;
    NSMutableData* tabStops;
    SInt32 charTop;
    
    SInt32 columnCount;
    SInt32 rowCount;
    
    SInt32 curX;
    SInt32 curY;
    SInt32 topMargin;
    SInt32 bottomMargin;
    TerminalAttribute currentAttribute;
    BOOL originWithinMargins;
    BOOL autoWrap;
    BOOL autoBackWrap;
    BOOL insertMode;
    BOOL autoReturnLineFeed;
    BOOL keypadNormal;
    BOOL inverseVideo;
    BOOL isVT100;
    
    SInt32 savedCurX;
    SInt32 savedCurY;
    TerminalAttribute savedAttribute;
    BOOL savedOriginWithinMargins;
    BOOL savedAutoWrap;
}

-(void)setColumnCount:(int)newCount;
-(void)setRowCountForHeight:(int)height;
-(void)initScreen;

-(void)setConnection:(SshConnection*)newConnection;
-(void)setCursorVisible:(BOOL)visible;


@end
