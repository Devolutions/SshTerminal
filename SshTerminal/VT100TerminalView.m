//
//  SshTerminal.m
//  LibSshTest
//
//  Created by Denis Vincent on 2015-06-03.
//  Copyright (c) 2015 Denis Vincent. All rights reserved.
//

#import "VT100TerminalView.h"

#define KEYPAD_ENTER 0x03

#define TA_BOLD 0x01
#define TA_UNDERLINE 0x02
#define TA_BLINK 0x04
#define TA_INVERSE 0x08
#define TA_INVISIBLE 0x10


@implementation VT100TerminalView

-(void)setConnection:(id<VT100Connection>)newConnection
{
    [connection release];
    connection = newConnection;
    [connection retain];
    [screen setConnection:newConnection];
    //[connection setDataDelegate:self];
}


-(void)setCursorVisible:(BOOL)visible
{
    if (visible != isCursorVisible)
    {
        isCursorVisible = visible;
        NSRect rect = [screen cursorRect];
        if (NSIsEmptyRect(rect) == NO)
        {
            [self displayRect:rect];
        }
    }
}


-(void)drawRect:(NSRect)dirtyRect
{
    [super drawRect:dirtyRect];
    if (isCursorVisible == NO)
    {
        return;
    }
    
    NSRect rect = [screen cursorRect];
    if (NSIsEmptyRect(rect) == NO)
    {
        NSColor* cursorColor = [NSColor colorWithDeviceWhite:1.0F alpha:0.5F];
        [cursorColor setFill];
        [NSBezierPath fillRect:rect];
    }
}


-(void)keyDown:(NSEvent *)theEvent
{
    if (isCursorVisible == NO)
    {
        return;
    }
    
    NSString* theKey = [theEvent charactersIgnoringModifiers];
    int length = (int)[theKey length];
    if (length == 0)
    {
        return;
    }
    
    if (theEvent.modifierFlags & NSCommandKeyMask)
    {
        if ([theKey characterAtIndex:0] == 'v')
        {
            NSPasteboard* pasteboard = [NSPasteboard generalPasteboard];
            NSArray* classes = [[NSArray alloc] initWithObjects:[NSString class], nil];
            NSDictionary* options = [NSDictionary dictionary];
            NSArray* copiedItems = [pasteboard readObjectsForClasses:classes options:options];
            [classes release];
            if (copiedItems != nil)
            {
                for (int i = 0; i < copiedItems.count; i++)
                {
                    NSString* string = [copiedItems objectAtIndex:i];
                    const char* chars = [string UTF8String];
                    [connection writeFrom:(const UInt8 *)chars length:(int)strlen(chars)];
                }
            }
        }
        else if ([theKey characterAtIndex:0] == 'c')
        {
            [super keyDown:theEvent];
        }
        return;
    }
    
    char specialSequence[16];
    specialSequence[0] = 0;
    
    if (length == 1)
    {
        unichar keyCode = [theKey characterAtIndex:0];
        switch (keyCode)
        {
            case KEYPAD_ENTER:
            {
                if (screen.keypadNormal == NO)
                {
                    sprintf(specialSequence, "\x1BOM");
                }
                else if (screen.autoReturnLineFeed == NO)
                {
                    sprintf(specialSequence, "\r");
                }
                else
                {
                    sprintf(specialSequence, "\r\n");
                }
                break;
            }
                
            case '\r':
            {
                if (screen.autoReturnLineFeed == YES)
                {
                    sprintf(specialSequence, "\r\n");
                }
                break;
            }
                
            case NSUpArrowFunctionKey:
            {
                sprintf(specialSequence, "\x1B[A");
                break;
            }
                
            case NSDownArrowFunctionKey:
            {
                sprintf(specialSequence, "\x1B[B");
                break;
            }
                
            case NSRightArrowFunctionKey:
            {
                sprintf(specialSequence, "\x1B[C");
                break;
            }
                
            case NSLeftArrowFunctionKey:
            {
                sprintf(specialSequence, "\x1B[D");
                break;
            }
                
            case NSDeleteFunctionKey:
            {
                sprintf(specialSequence, "\x08");
                break;
            }
                
            case '0':
            case '1':
            case '2':
            case '3':
            case '4':
            case '5':
            case '6':
            case '7':
            case '8':
            case '9':
            {
                if ((theEvent.modifierFlags & NSNumericPadKeyMask) && screen.keypadNormal == NO)
                {
                    sprintf(specialSequence, "\x1BO%c", keyCode - '0' + 'p');
                }
                break;
            }
                
            case '-':
            {
                if ((theEvent.modifierFlags & NSNumericPadKeyMask) && screen.keypadNormal == NO)
                {
                    sprintf(specialSequence, "\x1BOm");
                }
                break;
            }
                
            case '.':
            {
                if ((theEvent.modifierFlags & NSNumericPadKeyMask) && screen.keypadNormal == NO)
                {
                    sprintf(specialSequence, "\x1BOn");
                }
                break;
            }
                
            case '+':
            {
                if ((theEvent.modifierFlags & NSNumericPadKeyMask) && screen.keypadNormal == NO)
                {
                    sprintf(specialSequence, "\x1BOl");
                }
                break;
            }
                
            case ' ':
            {
                
                if (theEvent.modifierFlags & NSControlKeyMask)
                {
                    UInt8 nullChar = 0;
                    [connection writeFrom:&nullChar length:1];
                    return;
                }
                break;
            }
                
            case '`':
            {
                if (theEvent.modifierFlags & NSControlKeyMask)
                {
                    sprintf(specialSequence, "\x1E");
                }
                break;
            }
        }
    }

    
    const char* chars = (specialSequence[0] != 0 ? specialSequence : theEvent.characters.UTF8String );
    if (chars[0] != 0)
    {
        // Normal characters.
        int cLength = (int)strlen(chars);
        [connection writeFrom:(const UInt8*)chars length:cLength];
    }
}

-(void)keyUp:(NSEvent *)theEvent
{
    
}


-(void)setFrame:(NSRect)frame
{
    [super setFrame:frame];
    NSSize size = self.textContainer.containerSize;
    if (size.width != frame.size.width)
    {
        size.width = frame.size.width;
        [self.textContainer setContainerSize:size];
    }
}


-(void)setFrameSize:(NSSize)newSize
{
    [super setFrameSize:newSize];
    NSSize size = self.textContainer.containerSize;
    if (size.width != newSize.width)
    {
        size.width = newSize.width;
        [self.textContainer setContainerSize:size];
    }
}


-(void)setTerminalSize:(NSSize)newSize
{
    int newColumnCount = (self.frame.size.width - 4) / screen.fontWidth;
    int newRowCount = newSize.height/ screen.fontHeight;
    if (newColumnCount == columnCount && newRowCount == rowCount)
    {
        return;
    }
    columnCount = newColumnCount;
    rowCount = newRowCount;
    [screen setWidth:columnCount height:rowCount];
}


-(void)initScreen
{
    [self.layoutManager.textStorage deleteCharactersInRange:NSMakeRange(0, self.layoutManager.textStorage.length)];
    [screen resetScreen];
}


-(instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self != nil)
    {
        [self setVerticallyResizable:YES];
        [self setHorizontallyResizable:NO];
        [self setTextContainerInset:NSMakeSize(0, 0)];
        [self.textContainer setWidthTracksTextView:YES];
        [self.textContainer setHeightTracksTextView:NO];
        [self.textContainer setLineFragmentPadding:2];
        isCursorVisible = NO;

        screen = [[VT100ScreenBuffer alloc] init:self];

        self.backgroundColor = screen.backgroundColor;
    }
    
    return self;
}


-(void)dealloc
{
    [connection release];
    [screen release];
    
    [super dealloc];
}


@end
