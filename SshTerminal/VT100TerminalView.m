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


-(VT100ScreenBuffer*)screen
{
	return screen;
}


-(void)setConnection:(id<VT100Connection>)newConnection
{
    [connection release];
    connection = newConnection;
    [connection retain];
    [screen setConnection:newConnection];
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


-(BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)anItem
{
    SEL theAction = [anItem action];
    
    if (theAction == @selector(copy:))
    {
        return [super validateUserInterfaceItem:anItem];
    }
    else if (theAction == @selector(paste:))
    {
        if (isCursorVisible == YES)
        {
            return YES;
        }
        return NO;
    }
    
    return NO;
}


-(void)paste:(id)sender
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


-(void)mouseDown:(NSEvent *)event
{
    BOOL eventSent = [screen sendMouseEvent:event inView:self isUpEvent:NO];
    if (eventSent)
    {
        return;
    }
    
    [super mouseDown:event];
}


-(void)mouseUp:(NSEvent *)event
{
    BOOL eventSent = [screen sendMouseEvent:event inView:self isUpEvent:YES];
    if (eventSent)
    {
        return;
    }
    
    [super mouseUp:event];
}


-(void)insertText:(id)string replacementRange:(NSRange)replacementRange
{
	const char* chars = [string UTF8String];
	int cLength = (int)strlen(chars);
	if (markRange > 0)
	{
		for (int i = 0; i < markRange; i++)
		{
			[connection writeFrom:(const UInt8*)"\x1B[3~" length:4];
		}
		markRange = 0;
	}
	
	[connection writeFrom:(const UInt8*)chars length:cLength];
}


-(void)setMarkedText:(id)string selectedRange:(NSRange)selectedRange replacementRange:(NSRange)replacementRange
{
	markRange = [string length];
	const char* chars = [string UTF8String];
	int cLength = (int)strlen(chars);
	[connection writeFrom:(const UInt8*)chars length:cLength];
	for (int i = 0; i < markRange; i++)
	{
		[connection writeFrom:(const UInt8*)"\x1B[D" length:3];
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
	unichar keyCode = 0;
    if (length != 0)
    {
        keyCode = [theKey characterAtIndex:0];
    }
    
    if (theEvent.modifierFlags & NSCommandKeyMask)
    {
        if (keyCode == 'v')
        {
            [self paste:self];
        }
        else if (keyCode == 'c')
        {
            [super keyDown:theEvent];
        }
        return;
    }
    
    char specialSequence[16];
    specialSequence[0] = 0;
    
    if (length == 1)
    {
        switch (keyCode)
        {
			case NSDeleteCharacter:
			{
				sprintf(specialSequence, "\b");
				break;
			}
				
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
                
			case NSCarriageReturnCharacter:
            {
                if (screen.autoReturnLineFeed == YES)
                {
                    sprintf(specialSequence, "\r\n");
                }
				else
				{
					sprintf(specialSequence, "\r");
				}
                break;
            }
                
            case NSUpArrowFunctionKey:
            {
                sprintf(specialSequence, "\x1B[A");
                if (screen.cursorKeyAnsi == NO)
                {
                    specialSequence[1] = 'O';
                }
                break;
            }
                
            case NSDownArrowFunctionKey:
            {
                sprintf(specialSequence, "\x1B[B");
                if (screen.cursorKeyAnsi == NO)
                {
                    specialSequence[1] = 'O';
                }
                break;
            }
                
            case NSRightArrowFunctionKey:
            {
                sprintf(specialSequence, "\x1B[C");
                if (screen.cursorKeyAnsi == NO)
                {
                    specialSequence[1] = 'O';
                }
                break;
            }
                
            case NSLeftArrowFunctionKey:
            {
                sprintf(specialSequence, "\x1B[D");
                if (screen.cursorKeyAnsi == NO)
                {
                    specialSequence[1] = 'O';
                }
                break;
            }
                
            case NSDeleteFunctionKey:
            {
                sprintf(specialSequence, "\x1B[3~");
                break;
            }
				
            case NSPageUpFunctionKey:
            {
                if (screen.keypadNormal == YES)
                {
                    [super keyDown:theEvent];
                    return;
                }
                else
                {
                    sprintf(specialSequence, "\x1B[5~");
                }
                break;
            }
                
            case NSPageDownFunctionKey:
            {
                if (screen.keypadNormal == YES)
                {
                    [super keyDown:theEvent];
                    return;
                }
                else
                {
                    sprintf(specialSequence, "\x1B[6~");
                }
                break;
            }
                
            case NSHomeFunctionKey:
            {
                sprintf(specialSequence, "\x1B[H");
                if (screen.cursorKeyAnsi == NO)
                {
                    specialSequence[1] = 'O';
                }
                break;
            }
                
            case NSEndFunctionKey:
            {
                sprintf(specialSequence, "\x1B[F");
                if (screen.cursorKeyAnsi == NO)
                {
                    specialSequence[1] = 'O';
                }
                break;
            }
                
            case NSF1FunctionKey:
            {
                sprintf(specialSequence, "\x1BOP");
                break;
            }
                
            case NSF2FunctionKey:
            {
                sprintf(specialSequence, "\x1BOQ");
                break;
            }
                
            case NSF3FunctionKey:
            {
                sprintf(specialSequence, "\x1BOR");
                break;
            }
                
            case NSF4FunctionKey:
            {
                sprintf(specialSequence, "\x1BOS");
                break;
            }
                
            case NSF5FunctionKey:
            {
                sprintf(specialSequence, "\x1B[15~");
                break;
            }
                
            case NSF6FunctionKey:
            {
                sprintf(specialSequence, "\x1B[17~");
                break;
            }
                
            case NSF7FunctionKey:
            {
                sprintf(specialSequence, "\x1B[18~");
                break;
            }
                
            case NSF8FunctionKey:
            {
                sprintf(specialSequence, "\x1B[19~");
                break;
            }
                
            case NSF9FunctionKey:
            {
                sprintf(specialSequence, "\x1B[20~");
                break;
            }
                
            case NSF10FunctionKey:
            {
                sprintf(specialSequence, "\x1B[21~");
                break;
            }
                
            case NSF11FunctionKey:
            {
                sprintf(specialSequence, "\x1B[23~");
                break;
            }
                
            case NSF12FunctionKey:
            {
                sprintf(specialSequence, "\x1B[24~");
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

    if (specialSequence[0] != 0)
	{
		int cLength = (int)strlen(specialSequence);
		[connection writeFrom:(const UInt8*)specialSequence length:cLength];
		isKeyIntercepted = YES;
		return;
	}
	else if (theEvent.modifierFlags & NSControlKeyMask)
	{
		const char* chars = theEvent.characters.UTF8String;
		int cLength = (int)strlen(chars);
		[connection writeFrom:(const UInt8*)chars length:cLength];
		isKeyIntercepted = YES;
		return;
	}
	else if (theEvent.isARepeat)
	{
		const char* chars = theEvent.characters.UTF8String;
		int cLength = (int)strlen(chars);
		[connection writeFrom:(const UInt8*)chars length:cLength];
		return;
	}
	
	[super keyDown:theEvent];
}


-(void)keyUp:(NSEvent *)theEvent
{
	if (isCursorVisible == NO)
	{
		return;
	}
	
	if (isKeyIntercepted == YES)
	{
		isKeyIntercepted = NO;
		return;
	}
	
	[super keyUp:theEvent];
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
