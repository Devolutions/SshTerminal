//
//  VT100Screen.h
//  SshTerminal
//
//  Created by Denis Vincent on 2015-12-07.
//  Copyright (c) 2015 Denis Vincent. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "VT100Connection.h"
#import "SyntaxColoringItem.h"

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


@interface VT100ScreenBuffer : NSObject <VT100TerminalDataDelegate>
{
    id<VT100Connection> connection;
    NSMutableAttributedString* screen;
    NSTextView* textView;
    dispatch_block_t flushScreenBlock;
    NSLock* lock;
    
    NSFont* normalFont;
    NSFont* boldFont;
    NSColor* backColors[17];
    NSColor* textColors[17];
    
    NSMutableParagraphStyle* paragraphStyle;
    NSDictionary* newLineAttributes;
	NSDictionary* cursorAttributes;
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

	SInt32 altCurX;
	SInt32 altCurY;
	SInt32 altSavedCurX;
	SInt32 altSavedCurY;
    SInt32 bottomMargin;
    SInt32 columnCount;
    SInt32 curX;
    SInt32 curY;
	SInt32 cursorIndex;
    SInt32 firstInvalidLine;
    SInt32 lastInvalidLine;
    SInt32 rowCount;
    SInt32 savedCurX;
    SInt32 savedCurY;
    SInt32 savedCursorDeltaX;
    SInt32 savedCursorDeltaY;
    SInt32 savedCursorChar;
	SInt32 savedBottomMargin;
	SInt32 savedTopMargin;
    SInt32 screenOffset;
    SInt32 topMargin;
    
    UInt32 inIndex;
	
	int gSet;
	char gSets[4];
    
	BOOL isSingleCharShift;
    BOOL attributesNeedActualize;
    BOOL autoBackWrap;
    BOOL autoReturnLineFeed;
    BOOL autoWrap;
    BOOL cursorKeyAnsi;
    BOOL insertMode;
    BOOL inverseVideo;
    BOOL isVT100;
    BOOL keypadNormal;
    BOOL originWithinMargins;
    BOOL savedAutoWrap;
    BOOL savedOriginWithinMargins;
    BOOL sgrMouseEnable;
    BOOL urxvtMouseEnable;
	BOOL isAlternate;
	
	// SyntaxColoring specific.
	NSMutableArray* syntaxColoringItems;
	BOOL* syntaxColoringChangeMade;
}

@property(readonly)BOOL cursorKeyAnsi;
@property(readonly)BOOL keypadNormal;
@property(readonly)BOOL autoReturnLineFeed;
@property(readonly)NSColor* backgroundColor;
@property(readonly)float fontHeight;
@property(readonly)float fontWidth;

// SyntaxColoring specific.
@property(assign)NSMutableArray* syntaxColoringItems;
@property(assign)BOOL* syntaxColoringChangeMade;

-(instancetype)init:(NSTextView*)newTextView;
-(NSRect)cursorRect;
-(CursorPosition)cursorPositionAbsolute;
-(void)resetScreen;
-(void)setConnection:(id<VT100Connection>)newConnection;
-(void)setWidth:(int)newCount height:(int)height;
-(void)setFontWithname:(NSString*)newFontName size:(CGFloat)newFontSize;
-(void)setDefaultBackgroundColor:(NSColor*)background foregroundColor:(NSColor*)foreground;
-(void)setCursorBackgroundColor:(NSColor*)background foregroundColor:(NSColor*)foreground;
-(void)setColor:(NSColor*)color at:(int)index;

-(BOOL)sendMouseEvent:(NSEvent*)theEvent inView:(NSView*)view isUpEvent:(BOOL)isUp;

-(void)newDataAvailableIn:(UInt8*)buffer length:(int)size;
-(void)newDataAvailable;

// SyntaxColoring specific.
-(void)applyChanges;

@end
