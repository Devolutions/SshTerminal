//
//  VT100Screen.h
//  SshTerminal
//
//  Created by Denis Vincent on 2015-12-07.
//  Copyright (c) 2015 Denis Vincent. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "VT100Connection.h"

#define TERMINAL_BUFFER_SIZE 1024


typedef struct
{
    int x;
    int y;
} CursorPosition;

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


@interface VT100Screen : NSObject <VT100TerminalDataDelegate>
{
    id<VT100Connection> connection;
    NSMutableAttributedString* screen;
    NSTextView* textView;
    dispatch_block_t flushScreenBlock;
    NSLock* lock;
    
    NSFont* normalFont;
    NSFont* boldFont;
    NSColor* backColors[9];
    NSColor* textColors[9];
    
    NSMutableParagraphStyle* paragraphStyle;
    NSDictionary* newLineAttributes;
    NSAttributedString* blankLine;
    NSAttributedString* blankChar;
    NSAttributedString* lineFeed;
    NSMutableAttributedString* insert;
    NSMutableData* tabStops;
    
    UInt8 inBuffer[TERMINAL_BUFFER_SIZE];
    TerminalAttribute currentAttribute;
    TerminalAttribute savedAttribute;
    
    float fontHeight;
    float fontWidth;

    SInt32 bottomMargin;
    SInt32 columnCount;
    SInt32 curX;
    SInt32 curY;
    SInt32 firstInvalidLine;
    SInt32 lastInvalidLine;
    SInt32 rowCount;
    SInt32 savedCurX;
    SInt32 savedCurY;
    SInt32 savedCursorDeltaX;
    SInt32 savedCursorDeltaY;
    SInt32 savedCursorChar;
    SInt32 screenOffset;
    SInt32 topMargin;
    
    UInt32 inIndex;
    
    BOOL attributesNeedActualize;
    BOOL autoBackWrap;
    BOOL autoReturnLineFeed;
    BOOL autoWrap;
    BOOL insertMode;
    BOOL inverseVideo;
    BOOL isVT100;
    BOOL keypadNormal;
    BOOL originWithinMargins;
    BOOL savedAutoWrap;
    BOOL savedOriginWithinMargins;
}

@property(readonly)BOOL keypadNormal;
@property(readonly)BOOL autoReturnLineFeed;
@property(readonly)NSColor* backgroundColor;
@property(readonly)float fontHeight;
@property(readonly)float fontWidth;


-(instancetype)init:(NSTextView*)newTextView;
-(NSRect)cursorRect;
-(CursorPosition)cursorPositionAbsolute;
-(void)resetScreen;
-(void)setConnection:(id<VT100Connection>)newConnection;
-(void)setWidth:(int)newCount height:(int)height;

-(void)newDataAvailableIn:(UInt8*)buffer length:(int)size;
-(void)newDataAvailable;


@end
