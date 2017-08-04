//
//  VT100Screen.m
//  SshTerminal
//
//  Created by Denis Vincent on 2015-12-07.
//  Copyright (c) 2015 Denis Vincent. All rights reserved.
//

#import "VT100ScreenBuffer.h"


#ifdef DEBUG
//#define PRINT_INPUT 1
#endif

#define TA_BOLD 0x01
#define TA_UNDERLINE 0x02
#define TA_BLINK 0x04
#define TA_INVERSE 0x08
#define TA_INVISIBLE 0x10

NSString* TAName = @"TerminalAttributeName";


unichar gGraphicSet[] =
{
	0,		0,		0,		0,		0,		0,		0,		0,		0,		0,		0,		0,		0,		0,		0,		0,
	0,		0,		0,		0,		0,		0,		0,		0,		0,		0,		0,		0,		0,		0,		0,		0,
	0,		0,		0,		0,		0,		0,		0,		0,		0,		0,		0,		0,		0,		0,		0,		0,
	0,		0,		0,		0,		0,		0,		0,		0,		0,		0,		0,		0,		0,		0,		0,		0,
	0,		0,		0,		0,		0,		0,		0,		0,		0,		0,		0,		0,		0,		0,		0,		0,
	0,		0,		0,		0,		0,		0,		0,		0,		0,		0,		0,		0,		0,		0,		0,		0,
	0,		0,		0,		0,		0,		0,		0,		0,		0,		0, 0x2518, 0x2500, 0x250C, 0x2514, 0x253C,		0,
	0, 0x2500,		0,		0, 0x251C, 0x2524, 0x2534, 0x252C, 0x2502,		0,		0,		0,		0,		0,		0,		0,
};


@implementation VT100ScreenBuffer

@synthesize cursorKeyAnsi;
@synthesize keypadNormal;
@synthesize autoReturnLineFeed;
@synthesize fontHeight;
@synthesize fontWidth;

@synthesize syntaxColoringItems;
@synthesize syntaxColoringChangeMade;

-(void)setDefaultBackgroundColor:(NSColor *)background foregroundColor:(NSColor *)foreground
{
	backColors[0] = background;
	textView.backgroundColor = background;

	textColors[0] = foreground;
}


-(void)setCursorBackgroundColor:(NSColor *)background foregroundColor:(NSColor *)foreground
{
	[cursorAttributes release];
	cursorAttributes = [NSDictionary dictionaryWithObjectsAndKeys:background, NSBackgroundColorAttributeName, foreground, NSForegroundColorAttributeName, nil];
	[cursorAttributes retain];
}


-(void)setColor:(NSColor *)color at :(int)index
{
	backColors[index + 1] = color;
	textColors[index + 1] = color;
}


-(NSColor*)backgroundColor
{
    return backColors[0];
}


-(BOOL)sendMouseEvent:(NSEvent*)theEvent inView:(NSView*)view isUpEvent:(BOOL)isUp
{
    if (theEvent.buttonNumber != 0)
    {
        return NO;
    }
    
    char buffer[20];
    int button = (isUp ? 3 : 0);
    if (theEvent.modifierFlags & NSShiftKeyMask)
    {
        button &= 0x04;
    }
    if (theEvent.modifierFlags & NSControlKeyMask)
    {
        button &= 0x10;
    }
    if (sgrMouseEnable)
    {
        CursorPosition cur = [self cursorPositionFromEvent:theEvent inView:view];
        sprintf(buffer, "\x1B[<%d;%d;%d%c", button, cur.x, cur.y, (isUp ? 'm' : 'M'));
        [connection writeFrom:(UInt8*)buffer length:(int)strlen(buffer)];
        
        return YES;
    }
    else if (urxvtMouseEnable)
    {
        CursorPosition cur = [self cursorPositionFromEvent:theEvent inView:view];
        sprintf(buffer, "\x1B[%d;%d;%dM", button, cur.x, cur.y);
        [connection writeFrom:(UInt8*)buffer length:(int)strlen(buffer)];
        
        return YES;
    }
    
    return NO;
}


-(void)actualizeAttributesIn:(NSMutableAttributedString*)string inRange:(NSRange)range
{
	void (^change)(id, NSRange, BOOL*) = ^(id value, NSRange range, BOOL* stop)
	{
		NSNumber* number = value;
		if (number == nil)
		{
			number = [NSNumber numberWithInt:0];
		}
		TerminalAttribute attribute;
		attribute.all = [number intValue];
		NSMutableDictionary* dictionary = [NSMutableDictionary dictionaryWithDictionary:newLineAttributes];
		[dictionary setObject:number forKey:TAName];
		
		// Setup the colors.
		NSColor* backColor = backColors[attribute.backColor];
		NSColor* textColor = textColors[attribute.textColor];
		if (attribute.flags & TA_INVERSE)
		{
			[dictionary setObject:backColor forKey:NSForegroundColorAttributeName];
			[dictionary setObject:textColor forKey:NSBackgroundColorAttributeName];
		}
		else
		{
			[dictionary setObject:backColor forKey:NSBackgroundColorAttributeName];
			[dictionary setObject:textColor forKey:NSForegroundColorAttributeName];
		}
		
		// Setup the font.
		if (attribute.flags & TA_BOLD)
		{
			[dictionary setObject:boldFont forKey:NSFontAttributeName];
		}
		
		// Setup the underline attribute.
		if (attribute.flags & TA_UNDERLINE)
		{
			[dictionary setObject:[NSNumber numberWithInt:NSUnderlineStyleSingle] forKey:NSUnderlineStyleAttributeName];
		}
		
		// Paste to text.
		[string setAttributes:dictionary range:range];
	};
	
	[string enumerateAttribute:TAName inRange:range options:0 usingBlock:change];
}


-(void)actualizeAttributesIn:(NSMutableAttributedString*)string
{
	[self actualizeAttributesIn:string inRange:NSMakeRange(0, string.length)];
}


-(void)addLine:(SInt32)repeat
{
    if (firstInvalidLine - repeat < 0)
    {
        [self flushScreen];
    }
    
    lastInvalidLine = rowCount - 1;
    if (firstInvalidLine < rowCount)
    {
        firstInvalidLine -= repeat;
    }
    else
    {
        firstInvalidLine = lastInvalidLine - repeat + 1;
    }
    screenOffset += repeat;
    [screen deleteCharactersInRange:NSMakeRange(0, columnCount * repeat)];
    for (int i = 0; i < repeat; i++)
    {
        [screen appendAttributedString:blankLine];
    }
}


-(void)alignTest
{
    NSString* testString = [@"E" stringByPaddingToLength:columnCount withString:@"E" startingAtIndex:0];
    NSAttributedString* testLine = [[NSAttributedString alloc] initWithString:testString attributes:newLineAttributes];
    
    NSRange range = NSMakeRange(0, columnCount);
    for (int i = 0; i < rowCount; i++)
    {
        range.location = i * columnCount;
        [screen replaceCharactersInRange:range withString:testString];
    }
    [testLine release];

    firstInvalidLine = 0;
    lastInvalidLine = rowCount - 1;
}


// SyntaxColoring specific.
-(void)applyChanges
{
	if (*syntaxColoringChangeMade)
	{
		[self actualizeAttributesIn:[textView.layoutManager textStorage]];
		[self applySyntaxColoringIn:[textView.layoutManager textStorage]];
		*syntaxColoringChangeMade = false;
	}
}


-(void)applySyntaxColoringIn:(NSMutableAttributedString*)string
{
	if ([syntaxColoringItems count] == 0)
	{
		return;
	}
	void (^applySyntaxColoring)(id, NSRange, BOOL*) = ^(id value, NSRange range, BOOL* stop)
	{
		NSEnumerator *i = [syntaxColoringItems objectEnumerator];
		SyntaxColoringItem* item;
		
		int lastIndex = (int)[string length] - 1;
		NSString* str = [string string];
		while ((item = [i nextObject]) && item.isEnabled)
		{
			NSRange keywordRange;
			if (item.isCaseSensitive)
			{
				keywordRange = [str rangeOfString:item.keyword];
			}
			else
			{
				keywordRange = [str rangeOfString:item.keyword options:NSCaseInsensitiveSearch];
			}
			while (keywordRange.location != NSNotFound)
			{
				int previousIndex = (int)keywordRange.location - 1;
				int nextIndex = (int)keywordRange.location + item.keywordLen;
				unichar previousChar;
				unichar nextChar;
				if (previousIndex == -1)
				{
					previousChar = 1;
				}
				else {
					previousChar = [str characterAtIndex:previousIndex];
				}
				if (nextIndex > lastIndex)
				{
					nextChar = 1;
				}
				 else {
					nextChar = [str characterAtIndex:nextIndex];
				}
				if (
					item.isCompleteWord && (
					(previousChar >= 48 && previousChar <= 57) ||
					(previousChar >= 65 && previousChar <= 90) ||
					(previousChar >= 97 && previousChar <= 122) ||
					(previousChar >= 192 && previousChar <= 696) ||
					(nextChar >= 48 && nextChar <= 57) ||
					(nextChar >= 65 && nextChar <= 90) ||
					(nextChar >= 97 && nextChar <= 122) ||
					(nextChar >= 192 && nextChar <= 696) )
					)
				{
				}
				else
				{
					NSNumber* number = value;
					if (number == nil)
					{
						number = [NSNumber numberWithInt:0];
					}
					TerminalAttribute attribute;
					attribute.all = [number intValue];
					NSMutableDictionary* dictionary = [NSMutableDictionary dictionaryWithDictionary:newLineAttributes];
					[dictionary setObject:number forKey:TAName];
					
					// Setup the colors.
					NSColor* backColor = backColors[item.backColor];
					NSColor* textColor = textColors[item.textColor];
					[dictionary setObject:backColor forKey:NSBackgroundColorAttributeName];
					[dictionary setObject:textColor forKey:NSForegroundColorAttributeName];
					
					// Setup the underline attribute.
					if (item.isUnderlined)
					{
						[dictionary setObject:[NSNumber numberWithInt:NSUnderlineStyleSingle] forKey:NSUnderlineStyleAttributeName];
					}
					
					// Paste to text.
					[string setAttributes:dictionary range:keywordRange];
				}
				unsigned long offset = keywordRange.location + item.keywordLen;
				NSRange newRange = NSMakeRange(offset, lastIndex - offset);
				
				if (item.isCaseSensitive)
				{
					keywordRange = [str rangeOfString:item.keyword options:0 range:newRange];
				}
				else
				{
					keywordRange = [str rangeOfString:item.keyword options:NSCaseInsensitiveSearch range:newRange];
				}
			}
		}
	};
	
	[string enumerateAttribute:TAName inRange:NSMakeRange(0, string.length) options:0 usingBlock:applySyntaxColoring];
}


-(void)blankRangeInLine:(int)deleteCount
{
    // Blank from cursor a range of characters in line (characters after the range stay in place).
    if (deleteCount + curX > columnCount)
    {
        deleteCount = columnCount - curX;
    }
    if (deleteCount <= 0)
    {
        return;
    }
    
    int deleteOffset = curX + curY * columnCount;
    NSAttributedString* blankString = [blankLine attributedSubstringFromRange:NSMakeRange(0, deleteCount)];
    [screen replaceCharactersInRange:NSMakeRange(deleteOffset, deleteCount) withAttributedString:blankString];
    [self invalidateLine:curY];
}


-(void)cursorBackTab:(int)repeat
{
    char* tabs = tabStops.mutableBytes;
    while (repeat > 0)
    {
        do
        {
            if (curX <= 0)
            {
                return;
            }
            curX--;
        } while (tabs[curX] == 0);
        repeat++;
    }
	[self invalidateLine:curY];
}


-(void)cursorDown:(int)repeat
{
	[self invalidateLine:curY];
    curY += repeat;
    if (curY > bottomMargin)
    {
        curY = bottomMargin;
    }
	[self invalidateLine:curY];
}


-(void)cursorLeft:(int)repeat
{
    if (curX >= columnCount)
    {
        curX = columnCount - 1;
    }
    curX -= repeat;
    if (curX < 0)
    {
        curX = 0;
    }
	[self invalidateLine:curY];
}


-(CursorPosition)cursorPositionAbsolute   // UI, worker
{
    CursorPosition cur;
    cur.x = curX;
    cur.y = curY + screenOffset;
    return cur;
}


-(NSRect)cursorRect
{
    CursorPosition cur = [self cursorPositionAbsolute];
    NSRect rect = NSMakeRect(cur.x * fontWidth + 2, cur.y * fontHeight, fontWidth, fontHeight);
    
    return rect;
}


-(CursorPosition)cursorPositionFromEvent:(NSEvent*)theEvent inView:(NSView*)view
{
    NSPoint point = theEvent.locationInWindow;
    point = [view convertPoint:point fromView:nil];
    CursorPosition cur;
    cur.x = 1 + point.x / fontWidth;
    cur.y = 1 + point.y / fontHeight;
    
    return cur;
}


-(void)cursorRight:(int)repeat
{
    curX += repeat;
    if (curX >= columnCount)
    {
        curX = columnCount - 1;
    }
	[self invalidateLine:curY];
}


-(void)cursorTab:(int)repeat
{
    char* tabs = tabStops.mutableBytes;
    while (repeat > 0)
    {
        do
        {
            if (curX >= columnCount - 1)
            {
                curX = columnCount - 1;
                return;
            }
            curX++;
        } while (tabs[curX] == 0);
        repeat--;
    }
	[self invalidateLine:curY];
}


-(void)cursorUp:(int)repeat
{
	[self invalidateLine:curY];
    curY -= repeat;
    if (curY < topMargin)
    {
        curY = topMargin;
    }
	[self invalidateLine:curY];
}


-(void)cursorToRow:(int)row column:(int)col
{
	[self invalidateLine:curY];
    curX = col;
    
    if (originWithinMargins == NO)
    {
        curY = row;
        if (curY < 0)
        {
            curY = 0;
        }
        else if (curY >= rowCount)
        {
            curY = rowCount - 1;
        }
    }
    else
    {
        curY = row + topMargin;
        if (curY < topMargin)
        {
            curY = topMargin;
        }
        else if (curY > bottomMargin)
        {
            curY = bottomMargin;
        }
    }
    
    if (curX < 0)
    {
        curX = 0;
    }
    else if (curX >= columnCount)
    {
        curX = columnCount - 1;
    }
	[self invalidateLine:curY];
}


-(void)deleteInLine:(int)arg setAtrributes:(BOOL)isSetAttributes
{
	NSRange range = {0, 0};
    if (arg == -1 || arg == 0)
    {
        // Blank from cursor inclusive to end of line.
        range.location = curX + curY * columnCount;
        range.length = columnCount - curX;
        NSAttributedString* blankString = [blankLine attributedSubstringFromRange:NSMakeRange(0, range.length)];
        [screen replaceCharactersInRange:range withAttributedString:blankString];
    }
    else if (arg == 1)
    {
        // Blank from begining of line to cursor inclusive.
        range.location = curY * columnCount;
        range.length = curX + 1;
        NSAttributedString* blankString = [blankLine attributedSubstringFromRange:NSMakeRange(0, range.length)];
        [screen replaceCharactersInRange:range withAttributedString:blankString];
    }
    else if (arg == 2)
    {
        // Blank whole line.
        range.location = curY * columnCount;
        range.length = columnCount;
        [screen replaceCharactersInRange:range withAttributedString:blankLine];
    }
	if (isSetAttributes)
	{
		[screen addAttribute:TAName value:[NSNumber numberWithInt:currentAttribute.all] range:range];
	}
    [self invalidateLine:curY];
}


-(void)deleteInScreen:(int)arg
{
    NSRange range;
    range.length = columnCount;
    if (arg == -1 || arg == 0)
    {
        // Blank from cursor inclusive to end of screen.
        [self deleteInLine:0 setAtrributes:NO];   // Delete from cursor to end of line.
        for (int i = curY + 1; i < rowCount; i++)
        {
            range.location = i * columnCount;
            [screen replaceCharactersInRange:range withAttributedString:blankLine];
        }
        [self invalidateLine:curY];
        [self invalidateLine:rowCount - 1];
    }
    else if (arg == 1)
    {
        // Blank from begining of screen to cursor inclusive.
        for (int i = 0; i < curY; i++)
        {
            range.location = i * columnCount;
            [screen replaceCharactersInRange:range withAttributedString:blankLine];
        }
        [self deleteInLine:0 setAtrributes:NO];   // Delete from beginning of line to cursor inclusive.
        [self invalidateLine:0];
        [self invalidateLine:curY];
    }
    else if (arg == 2)
    {
        // Blank whole screen, cursor does not move.
        for (int i = 0; i < rowCount; i++)
        {
            range.location = i * columnCount;
            [screen replaceCharactersInRange:range withAttributedString:blankLine];
        }
        [self invalidateLine:0];
        [self invalidateLine:rowCount - 1];
    }
    else if (arg == 3)
    {
        // Blank whole screen and back-scroll.
    }
}


-(void)deleteRangeInLine:(int)deleteCount
{
    // Delete from cursor a range of characters in line (characters after the range are moved back).
    if (deleteCount + curX > columnCount)
    {
        deleteCount = columnCount - curX;
    }
    if (deleteCount < 1)
    {
        return;
    }
    
    int deleteOffset = curX + curY * columnCount;
    int moveCount = columnCount - curX - deleteCount;
    if (moveCount > 0)
    {
        [screen deleteCharactersInRange:NSMakeRange(deleteOffset, deleteCount)];
        NSAttributedString* blankString = [blankLine attributedSubstringFromRange:NSMakeRange(0, deleteCount)];
        [screen insertAttributedString:blankString atIndex:deleteOffset + moveCount];
    }
    else
    {
        NSAttributedString* blankString = [blankLine attributedSubstringFromRange:NSMakeRange(0, deleteCount)];
        [screen replaceCharactersInRange:NSMakeRange(deleteOffset, deleteCount) withAttributedString:blankString];
    }
    [self invalidateLine:curY];
}


-(BOOL)executeCommandAt:(int*)escIndex
{
    BOOL complete = NO;
    
    int i = *escIndex + 1;
    if (i >= inIndex)
    {
        return NO;
    }
    
    char c = inBuffer[i];
    if (c == '_')
    {
        // APC:
        i++;
        while (i + 1 < inIndex)
        {
            if (inBuffer[i] == 0x1B)
            {
                complete = YES;
                if (inBuffer[i + 1] == '\\')
                {
                    *escIndex = i + 1;
                }
                else
                {
                    *escIndex = i;
                }
                break;
            }
            else if (inBuffer[i] < 32)
            {
                [self excuteControlChar:inBuffer[i]];
            }
            i++;
        }
#ifdef PRINT_INPUT
        printf("APC\r\n");
#endif
    }
    else if (c == 'P')
    {
        // DCS:
        i++;
        while (i + 1 < inIndex)
        {
            if (inBuffer[i] == 0x1B)
            {
                complete = YES;
                if (inBuffer[i + 1] == '\\')
                {
                    *escIndex = i + 1;
                }
                else
                {
                    *escIndex = i;
                }
                break;
            }
            else if (inBuffer[i] < 32)
            {
                [self excuteControlChar:inBuffer[i]];
            }
            i++;
        }
#ifdef PRINT_INPUT
        printf("DCS\r\n");
#endif
    }
    else if (c == ']')
    {
        // OSC:
        i++;
        while (i + 1 < inIndex)
        {
            if (inBuffer[i] == 0x07)
            {
                complete = YES;
                *escIndex = i;
                break;
            }
            else if (inBuffer[i] == 0x1B)
            {
                complete = YES;
                if (inBuffer[i + 1] == '\\')
                {
                    *escIndex = i + 1;
                }
                else
                {
                    *escIndex =  i;
                }
                break;
            }
            else if (inBuffer[i] < 32)
            {
                [self excuteControlChar:inBuffer[i]];
            }
            i++;
        }
#ifdef PRINT_INPUT
        printf("OSC\r\n");
#endif
    }
    else if (c == '^')
    {
        // PM:
        i++;
        while (i + 1 < inIndex)
        {
            if (inBuffer[i] == 0x1B)
            {
                complete = YES;
                if (inBuffer[i + 1] == '\\')
                {
                    *escIndex = i + 1;
                }
                else
                {
                    *escIndex = i;
                }
                break;
            }
            else if (inBuffer[i] < 32)
            {
                [self excuteControlChar:inBuffer[i]];
            }
            i++;
        }
#ifdef PRINT_INPUT
        printf("PM\r\n");
#endif
    }
    else if (c == '[')
    {
        // CSI:
        i++;
        char command = 0;
        char modifier = 0;
        int j = i;
        int argCount = 1;
        while (i < inIndex)
        {
            if (inBuffer[i] >= '@' && inBuffer[i] < '~')
            {
                command = inBuffer[i];
                complete = YES;
                *escIndex = i;
                break;
            }
            else if (inBuffer[i] == ';')
            {
                argCount++;
            }
            else if (inBuffer[i] < 32)
            {
                [self excuteControlChar:inBuffer[i]];
            }
            
            i++;
        }
        
        if (complete == YES)
        {
            int allocCount = 10;
            if (argCount > 10)
            {
                allocCount = argCount;
            }
            int* args = malloc(allocCount * sizeof(int));
            memset(args, -1, allocCount * sizeof(int));
            int argStart = -1;
            int argIndex = 0;
            
#ifdef PRINT_INPUT
            char temp = inBuffer[i + 1];
            inBuffer[i + 1] = 0;
            printf("(CSI %s)", inBuffer + j);
            inBuffer[i + 1] = temp;
#endif
            modifier = inBuffer[j];
            if ((modifier >= '0' && modifier <= '9') || modifier == ';' || (modifier >= '@' && modifier <= '~'))
            {
                modifier = 0;
            }
            while (j <= i)
            {
                if (inBuffer[j] == ';' || j == i)
                {
                    if (argStart != -1)
                    {
                        NSString* argString = [[NSString alloc] initWithBytes:inBuffer + argStart length:j - argStart encoding:NSUTF8StringEncoding];
                        args[argIndex] = [argString intValue];
                        [argString release];
                        argStart = -1;
                    }
                    argIndex++;
                }
                else if (inBuffer[j] >= '0' && inBuffer[j] <= '9')
                {
                    if (argStart == -1)
                    {
                        argStart = j;
                    }
                }
                
                j++;
            }
            
            [self executeCsiCommand:command withModifier:modifier argValues:args argCount:argCount];
            
            free(args);
        }
    }
    else
    {
        if (c == ' ')
        {
            if (i + 1 < inIndex)
            {
                complete = YES;
                *escIndex = i + 1;
            }
        }
        else if (c == '#')
        {
            if (i + 1 < inIndex)
            {
                complete = YES;
                *escIndex = i + 1;
                if (inBuffer[i + 1] == '8')
                {
                    [self alignTest];
                }
            }
        }
        else if (c == '%')
        {
            if (i + 1 < inIndex)
            {
                complete = YES;
                *escIndex = i + 1;
            }
        }
        else if (c == '(')
        {
            if (i + 1 < inIndex)
            {
                complete = YES;
				gSets[0] = inBuffer[i + 1];
                *escIndex = i + 1;
            }
        }
        else if (c == ')')
        {
            if (i + 1 < inIndex)
            {
                complete = YES;
				gSets[1] = inBuffer[i + 1];
                *escIndex = i + 1;
            }
        }
        else if (c == '*')
        {
            if (i + 1 < inIndex)
            {
                complete = YES;
				gSets[2] = inBuffer[i + 1];
                *escIndex = i + 1;
            }
        }
        else if (c == '+')
        {
            if (i + 1 < inIndex)
            {
                complete = YES;
				gSets[3] = inBuffer[i + 1];
                *escIndex = i + 1;
            }
        }
        else
        {
            switch (c)
            {
                case '7':
                {
                    // Save cursor.
                    savedCurX = curX;
                    savedCurY = curY;
                    savedAttribute = currentAttribute;
                    savedAutoWrap = autoWrap;
                    savedOriginWithinMargins = originWithinMargins;
                    
                    // To implement:
                    // Character sets (G0 to G3) currently in GL and GR
                    // Selective erase attribute
                    // SS2 or SS3 functions sent
                    break;
                }
                    
                case '8':
                {
                    // Restore cursor.
					[self invalidateLine:curY];
                    curX = savedCurX;
                    curY = savedCurY;
					[self invalidateLine:curY];
                    currentAttribute = savedAttribute;
                    autoWrap = savedAutoWrap;
                    originWithinMargins = savedOriginWithinMargins;
                    
                    break;
                }
                    
                case 'A':
                {
                    // VT52 cursor up.
                    [self cursorUp:1];
                    break;
                }
                    
                case 'B':
                {
                    // VT52 cursor down.
                    [self cursorDown:1];
                    break;
                }
                    
                case 'C':
                {
                    // VT52 cursor right.
                    [self cursorRight:1];
                    break;
                }
                    
                case 'D':
                {
                    if (isVT100 == YES)
                    {
                        // Index (cursor down, add new line if needed).
                        if (curY == bottomMargin)
                        {
                            [self scrollFeed:1];
                        }
                        else
                        {
                            [self cursorDown:1];
                        }
                    }
                    else
                    {
                        // VT52 cursor left.
                        [self cursorLeft:1];
                        break;
                    }
                    break;
                }
                    
                case 'E':
                {
                    // Next line (cursor at the beginning of the next line, add new line if needed).
                    curX = 0;
                    if (curY == bottomMargin)
                    {
                        [self scrollFeed:1];
                    }
                    else
                    {
                        [self cursorDown:1];
                    }
                    
                    break;
                }
                    
                case 'F':
                {
                    // VT52 graphics mode.
                    break;
                }
                    
                case 'G':
                {
                    // VT52 end graphics mode.
                    break;
                }
                    
                case 'H':
                {
                    if (isVT100 == YES)
                    {
                        // Tab set.
                        int column = curX;
                        if (column >= columnCount)
                        {
                            column = columnCount + 1;
                        }
                        else if (column < 0)
                        {
                            column = 0;
                        }
                        char* tabs = tabStops.mutableBytes;
                        tabs[column] = 1;
                    }
                    else
                    {
                        // VT52 home position.
                        [self cursorToRow:0 column:0];
                    }
                    break;
                }

				case 'J':
                {
                    // VT52 delete from cursor to end of screen.
                    [self deleteInScreen:0];
                    break;
                }
                    
                case 'K':
                {
                    // VT52 delete from cursor to end of line.
                    [self deleteInLine:0 setAtrributes:NO];
                    break;
                }
                    
                case 'I':
                    // VT52 reverse line feed.
                case 'M':
                {
                    // Reverse index (cursor up).
                    if (curY == topMargin)
                    {
                        [self scrollBack:1];
                    }
                    else
                    {
                        [self cursorUp:1];
                    }
                    break;
                }
					
				case 'N':
				{
					isSingleCharShift = YES;
					gSet = 2;
					break;
				}
					
				case 'O':
				{
					isSingleCharShift = YES;
					gSet = 3;
					break;
				}
					
                case 'Y':
                {
                    // VT52 move cursor.
                    if (i + 2 >= inIndex)
                    {
                        return complete;
                    }
                    int row = inBuffer[i + 1] - 32;
                    int col = inBuffer[i + 2] - 32;
                    [self cursorToRow:row column:col];
                    i += 2;
                    break;
                }
                    
                case 'Z':
                {
                    // VT52 identity.
                    [connection writeFrom:(const UInt8 *)"\x1B/Z" length:3];
                    break;
                }
					
				case 'n':
				{
					gSet = 2;
					break;
				}
					
				case 'o':
				{
					gSet = 2;
					break;
				}
					
                case '=':
                {
                    keypadNormal = NO;
                    break;
                }
                    
                case '>':
                {
                    keypadNormal = YES;
                    break;
                }
                    
                case '<':
                {
                    // VT52 exit, return to VT100.
                    isVT100 = YES;
                    break;
                }
                    
                default:
                {
                    break;
                }
            }
            complete = YES;
            *escIndex = i;
        }
        
#ifdef PRINT_INPUT
		if (*escIndex == i)
		{
			printf("(ESC %c)\r\n", c);
		}
		else
		{
			printf("(ESC %c%c)\r\n", c, inBuffer[i + 1]);
		}
#endif
    }
    
    return complete;
}


-(void)excuteControlChar:(char)c
{
    switch (c)
    {
        case 0x05:
        {
            UInt8 ack = 0x06;
            [connection writeFrom:&ack length:1];
            break;
        }
            
        case 0x08:
        {
            // Backspace:
            if (autoBackWrap == NO)
            {
                [self cursorLeft:1];
            }
            else
            {
                if (curX == 0)
                {
					[self invalidateLine:curY];
                    curX = columnCount - 1;
                    if (curY == topMargin)
                    {
                        [self scrollBack:1];
                    }
                    else
                    {
                        curY--;
                    }
					[self invalidateLine:curY];
                }
                else
                {
                    [self cursorLeft:1];
                }
            }
            break;
        }
            
        case 0x09:
        {
            // Tab:
            [self cursorTab:1];
            break;
        }
            
        case '\r':
        {
            curX = 0;
			[self invalidateLine:curY];
            break;
        }
            
        case '\n':
        case 0x0B:
        case 0x0C:
        {
            if (curY >= bottomMargin)
            {
                [self scrollFeed:1];
            }
            else
            {
                [self cursorDown:1];
            }
            if (autoReturnLineFeed == YES)
            {
                curX = 0;
				[self invalidateLine:curY];
            }
            break;
        }
			
		case 0x0E:
		{
			gSet = 1;
			break;
		}
			
		case 0x0F:
		{
			gSet = 0;
			break;
		}
    }
    
#ifdef PRINT_INPUT
    printf("(%02X)", c);
    if (c == '\n')
    {
        printf("\r\n");
    }
#endif
}


-(void)executeCsiCommand:(char)command withModifier:(char)modifier argValues:(int*)args argCount:(int)argCount
{
    switch (command)
    {
        case 'A':
        {
            // Move cursor up.
            int repeat = (args[0] > 1 ? args[0] : 1);
            [self cursorUp:repeat];
            break;
        }
            
        case 'B':
        {
            // Move cursor down.
            int repeat = (args[0] > 1 ? args[0] : 1);
            [self cursorDown:repeat];
            break;
        }
            
        case 'C':
        {
            // Move cursor right.
            int repeat = (args[0] > 1 ? args[0] : 1);
			if (curX + repeat >= columnCount)
			{
				repeat = columnCount - curX;
			}
            [self cursorRight:repeat];
            break;
        }
            
        case 'D':
        {
            // Move cursor left.
            int repeat = (args[0] > 1 ? args[0] : 1);
            [self cursorLeft:repeat];
            break;
        }
            
        case 'E':
        {
            // Move cursor to beginning of next line.
            int repeat = (args[0] > 1 ? args[0] : 1);
            if (curY <= bottomMargin && repeat > bottomMargin - curY)
            {
                // The repeat will cause the cursor to go past the bottom margin.
                SInt32 scrollRepeat = repeat - bottomMargin - curY;
                [self scrollFeed:scrollRepeat];
                repeat = bottomMargin - curY;
            }
            [self cursorDown:repeat];
            curX = 0;
			[self invalidateLine:curY];
            break;
        }
            
        case 'F':
        {
            // Move cursor to beginning of preceding line.
            int repeat = (args[0] > 1 ? args[0] : 1);
            if (curY >= topMargin && repeat > curY - topMargin)
            {
                // The repeat will cause the cursor to go past the top margin.
                SInt32 scrollRepeat = repeat - curY - topMargin;
                [self scrollBack:scrollRepeat];
            }
            [self cursorUp:repeat];
            curX = 0;
			[self invalidateLine:curY];
            
            break;
        }
            
        case 'G':
        case '`':
        {
            // Move cursor to position in line.
            curX = (args[0] > 0 ? args[0] - 1 : 0);
            if (curX >= columnCount)
            {
                curX = columnCount - 1;
            }
			[self invalidateLine:curY];
            
            break;
        }
            
        case 'H':
        case 'f':
        {
            // Move cursor to position in screen.
            int row = (args[0] > 0 ? args[0] - 1 : 0);
            int col = (args[1] > 0 ? args[1] - 1 : 0);
            [self cursorToRow:row column:col];
            break;
        }
            
        case 'J':
        {
            // Delete in screen.
            [self deleteInScreen:args[0]];
            break;
        }
            
        case 'K':
        {
            // Delete in line.
			[self deleteInLine:args[0] setAtrributes:YES];
            break;
        }
            
        case 'L':
        {
            // Insert blank lines in screen at the current line (lines after the insterted lines are moved down).
            SInt32 insertCount = (args[0] < 0 ? 1 : args[0]);
            if (curY >= topMargin && curY < bottomMargin && insertCount > 0)
            {
                [self scrollBack:insertCount];
            }
            
            break;
        }
            
        case 'M':
        {
            // Delete lines in screen from the current line (lines after the deleted lines are moved up).
            int deleteCount = (args[0] >= 0 ? args[0] : 1);
            if (curY >= topMargin && curY < bottomMargin && deleteCount > 0)
            {
                [self scrollFeed:deleteCount];
            }
            
            break;
        }
            
        case 'P':
        {
            // Delete from cursor a range of characters in line (characters after the range are moved back).
            int deleteCount = (args[0] >= 0 ? args[0] : 1);
            [self deleteRangeInLine:deleteCount];
            break;
        }
            
        case 'S':
        {
            int scrollCount = (args[0] > 0 ? args[0] : 0);
            [self scrollFeed:scrollCount];
            break;
        }
            
        case 'T':
        {
            if (argCount < 2)
            {
                int scrollCount = (args[0] > 0 ? args[0] : 0);
                [self scrollBack:scrollCount];
            }
            break;
        }
            
        case 'X':
        {
            // Delete from cursor a range of characters in line.
            int deleteCount = (args[0] >= 0 ? args[0] : 1);
            [self blankRangeInLine:deleteCount];
            break;
        }
            
        case 'Z':
        {
            int repeat = (args[0] > 0 ? args[0] : 1);
            [self cursorBackTab:repeat];
            break;
        }
            
        case '@':
        {
            // Insert blank characters from cursor in line (characters after the cursor are moved forward).
            int insertCount = (args[0] >= 0 ? args[0] : 1);
            [self insertInLine:insertCount];
            break;
        }
            
        case 'c':
        {
            // Device request.
            static const UInt8 reply[] = { 0x1B, '[', '?', '1', ';', '2', 'c' };
            [connection writeFrom:reply length:sizeof(reply)];
            
            break;
        }
            
        case 'd':
        {
			[self invalidateLine:curY];
            curY = (args[0] > 0 ? args[0] - 1 : 0);
            if (curY >= rowCount)
            {
                curY = rowCount - 1;
            }
			[self invalidateLine:curY];
            break;
        }
            
        case 'g':
        {
            // Clear tab.
            int mode = (args[0] < 0 ? 0 : args[0]);
            if (mode == 0)
            {
                // Clear current column.
                int column = curX;
                if (column >= columnCount)
                {
                    column = columnCount + 1;
                }
                else if (column < 0)
                {
                    column = 0;
                }
                char* tabs = tabStops.mutableBytes;
                tabs[column] = 0;
            }
            else if (mode == 3)
            {
                // Clear all tab.
                NSRange clearRange;
                clearRange.location = 0;
                clearRange.length = tabStops.length;
                [tabStops resetBytesInRange:clearRange];
            }
            break;
        }
            
        case 'h':
        {
            // Set a mode.
            if (modifier == 0)
            {
                for (int i = 0; i < argCount; i++)
                {
                    if (args[i] > -1)
                    {
                        switch (args[i])
                        {
                            case 4:
                            {
                                // Insert mode.
                                insertMode = YES;
                                break;
                            }
                                
                            case 20:
                            {
                                // Line feed mode.
                                autoReturnLineFeed = YES;
                                break;
                            }
                        }
                    }
                }
            }
            else if (modifier == '?')
            {
                for (int i = 0; i < argCount; i++)
                {
                    if (args[i] > -1)
                    {
                        switch (args[i])
                        {
                            case 1:
                            {
                                cursorKeyAnsi = NO;
                                break;
                            }
                                
                            case 2:
                            {
								gSets[0] = 'B';
								gSets[1] = 'B';
								gSets[2] = 'B';
								gSets[3] = 'B';
								gSet = 0;
								isSingleCharShift = NO;
                                isVT100 = YES;
                                break;
                            }
                                
                            case 3:
                            {
                                // Column mode (it implies a clear screen and a cursor home position).
                                [self deleteInScreen:2];
                                [self cursorToRow:0 column:0];
                                break;
                            }
                                
                            case 5:
                            {
                                if (inverseVideo == NO)
                                {
                                    inverseVideo = YES;
                                    NSColor* swapColor = backColors[0];
                                    backColors[0] = textColors[0];
                                    textColors[0] = swapColor;
                                    [self actualizeAttributesIn: screen];
                                    [self actualizeAttributesIn:[textView.layoutManager textStorage]];
                                    textView.backgroundColor = backColors[0];
                                }
                                break;
                            }
                                
                            case 6:
                            {
                                originWithinMargins = YES;
                                [self cursorToRow:0 column:0];
                                break;
                            }
                                
                            case 7:
                            {
                                autoWrap = YES;
                                break;
                            }
                                
                            case 45:
                            {
                                autoBackWrap = YES;
                                break;
                            }
                                
                            case 1006:
                            {
                                sgrMouseEnable = YES;
                                break;
                            }
                                
                            case 1015:
                            {
                                urxvtMouseEnable = YES;
                                break;
                            }
								
							case 1049:
							{
								[self scrollFeed:curY];
								[self scrollFeed:1];   // Scroll one more line to get rid of the top incomplete line (done this way because scrollFeed clips the repeat count).
								isAlternate = YES;
								savedBottomMargin = bottomMargin;
								savedTopMargin = topMargin;
								altCurX = curX;
								altCurY = curY;
								altSavedCurX = savedCurX;
								altSavedCurY = savedCurY;
								[self invalidateLine:curY];
								curX = 0;
								curY = 0;
								[self invalidateLine:curY];
							}
                        }
                    }
                }
            }
            break;
        }
            
        case 'l':
        {
            // Reset a mode.
            if (modifier == 0)
            {
                for (int i = 0; i < argCount; i++)
                {
                    if (args[i] <= 0)
                    {
                        continue;
                    }
                    switch (args[i])
                    {
                        case 4:
                        {
                            // Insert mode.
                            insertMode = NO;
                            break;
                        }
                            
                        case 20:
                        {
                            // Line feed mode.
                            autoReturnLineFeed = NO;
                            break;
                        }
                    }
                }
            }
            else if (modifier == '?')
            {
                for (int i = 0; i < argCount; i++)
                {
                    if (args[i] <= 0)
                    {
                        continue;
                    }
                    switch (args[i])
                    {
                        case 1:
                        {
                            cursorKeyAnsi = YES;
                            break;
                        }
                            
                        case 2:
                        {
                            isVT100 = NO;
                            break;
                        }
                            
                        case 3:
                        {
                            // Column mode (it implies a clear screen and a cursor home position).
                            [self deleteInScreen:2];
                            [self cursorToRow:0 column:0];
                            break;
                        }
                            
                        case 5:
                        {
                            if (inverseVideo == YES)
                            {
                                inverseVideo = NO;
                                NSColor* swapColor = backColors[0];
                                backColors[0] = textColors[0];
                                textColors[0] = swapColor;
                                [self actualizeAttributesIn: screen];
                                [self actualizeAttributesIn:[textView.layoutManager textStorage]];
                                textView.backgroundColor = backColors[0];
                            }
                            break;
                        }
                            
                        case 6:
                        {
                            originWithinMargins = NO;
                            [self cursorToRow:0 column:0];
                            break;
                        }
                            
                        case 7:
                        {
                            autoWrap = NO;
                            break;
                        }
                            
                        case 45:
                        {
                            autoBackWrap = NO;
                            break;
                        }
                            
                        case 1006:
                        {
                            sgrMouseEnable = NO;
                            break;
                        }
                            
                        case 1015:
                        {
                            urxvtMouseEnable = NO;
                        }
							
						case 1049:
						{
							isAlternate = NO;
							topMargin = savedTopMargin;
							bottomMargin = savedBottomMargin;
							[self invalidateLine:curY];
							curX = 0;
							curY = 0;
							[self invalidateLine:curY];
							[self deleteInScreen:2];
						}
                    }
                }
            }
            break;
        }
            
        case 'm':
        {
            // Character attributes.
            for (int i = 0; i < argCount; i++)
            {
                int arg = args[i];
                if (arg <= 0)
                {
                    // Reset all attributes.
                    currentAttribute.all = 0;
                    continue;
                }
                if (arg >= 30 && arg <= 37)
                {
                    currentAttribute.textColor = arg - 29;
                    continue;
                }
                if (arg >= 40 && arg <= 47)
                {
                    currentAttribute.backColor = arg - 39;
                    continue;
                }
                if (arg >= 90 && arg <= 97)
                {
                    currentAttribute.textColor = arg - 89 + 8;
                    continue;
                }
                if (arg >= 100 && arg <= 107)
                {
                    currentAttribute.backColor = arg - 99 + 8;
                    continue;
                }
                switch (arg)
                {
                    case 1:
                    {
                        currentAttribute.flags |= TA_BOLD;
                        break;
                    }
                        
                    case 4:
                    {
                        currentAttribute.flags |= TA_UNDERLINE;
                        break;
                    }
                        
                    case 5:
                    {
                        currentAttribute.flags |= TA_BLINK;
                        break;
                    }
                        
                    case 7:
                    {
                        currentAttribute.flags |= TA_INVERSE;
                        break;
                    }
                        
                    case 8:
                    {
                        currentAttribute.flags |= TA_INVISIBLE;
                        break;
                    }
                        
                    case 22:
                    {
                        currentAttribute.flags &= ~TA_BOLD;
                        break;
                    }
                        
                    case 24:
                    {
                        currentAttribute.flags &= ~TA_UNDERLINE;
                        break;
                    }
                        
                    case 25:
                    {
                        currentAttribute.flags &= ~TA_BLINK;
                        break;
                    }
                        
                    case 27:
                    {
                        currentAttribute.flags &= ~TA_INVERSE;
                        break;
                    }
                        
                    case 28:
                    {
                        currentAttribute.flags &= ~TA_INVISIBLE;
                        break;
                    }
                        
                    case 39:
                    {
                        currentAttribute.textColor = 0;
                        break;
                    }
                        
                    case 49:
                    {
                        currentAttribute.backColor = 0;
                        break;
                    }
                }
            }
            break;
        }
            
        case 'n':
        {
            if (modifier == 0)
            {
                if (args[0] == 5)
                {
                    [connection writeFrom:(const UInt8*)"\x1B[0n" length:4];
                }
                else if (args[0] == 6)
                {
                    UInt8 report[16];
                    SInt32 row = curY + 1;
                    if (originWithinMargins == YES)
                    {
                        row -= topMargin;
                    }
                    SInt32 col = curX + 1;
                    sprintf((char*)report, "\x1B[%d;%dR", (int)row, (int)col);
                    [connection writeFrom:report length:(int)strlen((char*)report)];
                }
            }
            break;
        }
            
        case 'r':
        {
            // Set the top and bottom margins, set the cursor position to the origin.
            // The top and bottom margins must be within the terminal screen,
            // and the top margin must be less than the bottom margin (equal is not OK).
            topMargin = (args[0] < 1 ? 0 : args[0] - 1);
            bottomMargin = (args[1] < 1 ? rowCount - 1 : args[1] - 1);
            
            if (topMargin >= rowCount)
            {
                topMargin = rowCount - 2;
            }
            if (bottomMargin >= rowCount)
            {
                bottomMargin = rowCount - 1;
            }
            if (topMargin + 1 > bottomMargin)
            {
                if (topMargin == 0)
                {
                    bottomMargin = 1;
                }
                else
                {
                    topMargin = bottomMargin - 1;
                }
            }
            
            [self cursorToRow:0 column:0];
            break;
        }
    }
}


-(void)flushScreen
{
    if (lastInvalidLine < 0)
    {
        return;
    }
	
	[self actualizeAttributesIn:screen];
	[self applySyntaxColoringIn:screen];
    
    flushScreenBlock = ^{
        NSLayoutManager* layout = textView.layoutManager;
        NSTextStorage* storage = [layout textStorage];
        if (attributesNeedActualize == YES)
        {
            [self actualizeAttributesIn:storage];
        }
        SInt32 updateLine = screenOffset + firstInvalidLine;
        int updateLineStart = 0;
        
        // Count the number of lines, find the first line that needs updating and the line corresponding to the top of the screen.
        int lineCount = 0;
        int screenTopGlyph = 0;
        int glyphCount = (int)[layout numberOfGlyphs];
        int glyphIndex = 0;
        while (glyphIndex < glyphCount)
        {
            NSRange glyphRange;
            [layout lineFragmentRectForGlyphAtIndex:glyphIndex effectiveRange:&glyphRange];
            glyphIndex = (int)glyphRange.location + (int)glyphRange.length;
            if (lineCount == screenOffset)
            {
                screenTopGlyph = (int)glyphRange.location;
            }
            if (lineCount == updateLine)
            {
                updateLineStart = (int)[layout characterIndexForGlyphAtIndex:glyphRange.location];
            }
            lineCount++;
        }
        if (lineCount == 0)
        {
            lineCount = 1;
        }
        
        // Delete from the text view the part that needs updating.
        [storage beginEditing];
		if (self->cursorIndex < storage.length)
		{
			[self actualizeAttributesIn:storage inRange:NSMakeRange(self->cursorIndex, 1)];
		}
        if (updateLine < lineCount)
        {
            NSRange range = NSMakeRange(updateLineStart, storage.length - updateLineStart);
            [storage deleteCharactersInRange:range];
        }
        else
        {
            while (lineCount <= updateLine)
            {
                [storage appendAttributedString:lineFeed];
                lineCount++;
            }
        }
        
        // Transfer from the screen to the view.
        if (screenOffset == 0)
        {
            if (lastInvalidLine < lineCount - 1)
            {
                lastInvalidLine = lineCount - 1;
            }
        }
        else
		{
            lastInvalidLine = rowCount - 1;
        }
        
        for (int l = firstInvalidLine; l <= lastInvalidLine; l++)
        {
            int lineStart = l * columnCount;
            NSAttributedString* screenLine = [screen attributedSubstringFromRange:NSMakeRange(lineStart, columnCount)];
			if (l == curY)
			{
				self->cursorIndex = (SInt32)storage.length + curX;
			}
            [storage appendAttributedString:screenLine];
			if (l == curY && [textView cursorVisible] && self->cursorIndex < storage.length)
			{
				[storage addAttributes:cursorAttributes range:NSMakeRange(self->cursorIndex, 1)];
			}
            
            if (l < lastInvalidLine)
            {
                [storage appendAttributedString:lineFeed];
            }
        }
        [storage endEditing];
        
        // Scroll to the updated portion of the view.
        [textView setSelectedRange:NSMakeRange(storage.length, 0)];
        [textView scrollRangeToVisible:NSMakeRange(storage.length, 0)];

        firstInvalidLine = INT_MAX;
        lastInvalidLine = -1;
        
        // Find the cursor position in the text view.
        glyphIndex = screenTopGlyph;
        glyphCount = (int)[layout numberOfGlyphs];
        int line = 0;
        while (glyphIndex < glyphCount)
        {
            NSRange glyphRange;
            [layout lineFragmentRectForGlyphAtIndex:glyphIndex effectiveRange:&glyphRange];
            glyphIndex = (int)glyphRange.location + (int)glyphRange.length;
            if (line == curY)
            {
                int lineStart = (int)[layout characterIndexForGlyphAtIndex:glyphRange.location];
                int lineEnd = (int)[layout characterIndexForGlyphAtIndex:glyphRange.location + glyphRange.length];
                int lineLength = lineEnd - lineStart;
                if (curX >= lineLength)
                {
                    savedCursorChar = lineEnd - 1;
                    savedCursorDeltaY = 0;
                    savedCursorDeltaX = curX - lineLength + 1;
                }
                else
                {
                    savedCursorChar = lineStart + curX;
                    savedCursorDeltaY = 0;
                    savedCursorDeltaX = 0;
                }
                break;
            }
            line++;
        }
        if (curY > line)
        {
            savedCursorChar = (int)storage.length;
            savedCursorDeltaY = screenOffset + curY - lineCount;
            savedCursorDeltaX = curX;
        }
    };
    
    [lock unlock];
    dispatch_sync(dispatch_get_main_queue(), ^{ [self flushScreenOnUI]; });
    [lock lock];
}


-(void)flushScreenOnUI
{
    if ([lock tryLock] == YES)
    {
        if (flushScreenBlock != nil)
        {
            flushScreenBlock();
            Block_release(flushScreenBlock);
            flushScreenBlock = nil;
        }
        [lock unlock];
    }
}


-(void)getLock
{
    while (1)
    {
        [lock lock];
        if (flushScreenBlock == nil)
        {
            break;
        }
        flushScreenBlock();
        Block_release(flushScreenBlock);
        flushScreenBlock = nil;
        [lock unlock];
    }
}


-(void)insertInLine:(int)insertCount
{
    if (insertCount + curY >= rowCount)
    {
        insertCount = rowCount - curY - 1;
    }
    
    if (insertCount > 0)
    {
        int insertOffset = curX + curY * columnCount;
        int moveCount = columnCount - curX - insertCount;
        if (moveCount > 0)
        {
            int deleteOffset = columnCount - insertCount + curY * columnCount;
            [screen deleteCharactersInRange:NSMakeRange(deleteOffset, insertCount)];
            NSAttributedString* blankString = [blankLine attributedSubstringFromRange:NSMakeRange(0, insertCount)];
            [screen insertAttributedString:blankString atIndex:insertOffset];
        }
        else
        {
            [screen replaceCharactersInRange:NSMakeRange(insertOffset, insertCount) withAttributedString:blankLine];
        }
        [self invalidateLine:curY];
    }
}


-(void)invalidateLine:(int)line
{
    if (line < firstInvalidLine)
    {
        firstInvalidLine = line;
    }
    if (line > lastInvalidLine)
    {
        lastInvalidLine = line;
    }
}


-(void)newDataAvailableIn:(UInt8*)buffer length:(int)size
{
    [lock lock];
    while (size > 0)
    {
        int copySize = (size > TERMINAL_BUFFER_SIZE - inIndex ? TERMINAL_BUFFER_SIZE - inIndex : size);
        memcpy(inBuffer + inIndex, buffer, copySize);
        inIndex += copySize;
        [self newDataAvailable];
        size -= copySize;
        buffer += copySize;
    }
    
    [self flushScreen];
    [lock unlock];
}


-(void)newDataAvailable
{
    char charBuffer[5];
    int i;
    for (i = 0; i < inIndex; i++)
    {
        UInt8 c = inBuffer[i];
        if (c == 0x1B)
        {
            // Escape: parse escape sequence.
            int escIndex = i;
            BOOL complete = [self executeCommandAt:&i];
            if (complete == NO)
            {
                memmove(inBuffer, inBuffer + escIndex, inIndex - escIndex);
                break;
            }
        }
        else if (c < 32)
        {
            [self excuteControlChar:c];
        }
        else
        {
            // Normal char:
            if (curX >= columnCount)
            {
                if (autoWrap == YES)
                {
                    if (curY == bottomMargin)
                    {
                        [self scrollFeed:1];
                        curX = 0;
						[self invalidateLine:curY];
                    }
                    else
                    {
                        [self cursorDown:1];
                        curX = 0;
						[self invalidateLine:curY];
                    }
                }
                else
                {
                    curX = columnCount - 1;
					[self invalidateLine:curY];
                }
            }
            
            if ((c & 0x80) == 0)
            {
                charBuffer[0] = c;
                charBuffer[1] = 0;
            }
            else if ((c & 0xE0) == 0xC0)
            {
                if (i + 1 >= inIndex)
                {
                    memmove(inBuffer, inBuffer + i, inIndex - i);
                    break;
                }
                charBuffer[0] = inBuffer[i++];
                charBuffer[1] = inBuffer[i];
                charBuffer[2] = 0;
            }
            else if ((c & 0xF0) == 0xE0)
            {
                if (i + 2 >= inIndex)
                {
                    memmove(inBuffer, inBuffer + i, inIndex - i);
                    break;
                }
                charBuffer[0] = inBuffer[i++];
                charBuffer[1] = inBuffer[i++];
                charBuffer[2] = inBuffer[i];
                charBuffer[3] = 0;
            }
            else if ((c & 0xF8) == 0xF0)
            {
                if (i + 3 >= inIndex)
                {
                    memmove(inBuffer, inBuffer + i, inIndex - i);
                    break;
                }
                charBuffer[0] = inBuffer[i++];
                charBuffer[1] = inBuffer[i++];
                charBuffer[2] = inBuffer[i++];
                charBuffer[3] = inBuffer[i];
                charBuffer[4] = 0;
            }
            NSString* charString = [NSString stringWithUTF8String:charBuffer];
			if (gSets[gSet] == '0' && (c & 0x80) == 0 && gGraphicSet[c] != 0)
			{
				charString = [NSString stringWithCharacters:gGraphicSet + c length:1];
			}
			if (isSingleCharShift)
			{
				gSet = 0;
				isSingleCharShift = NO;
			}
            if (charString == NULL)
            {
                charString = @" ";
            }
            [insert.mutableString setString:charString];
            NSRange range;
            range.location = curY * columnCount + curX;
            range.length = [insert length];
            [insert setAttributes:newLineAttributes range:NSMakeRange(0, range.length)];
            if (insertMode == YES)
            {
                [self insertInLine:(int)range.length];
            }
            [screen replaceCharactersInRange:range withAttributedString:insert];
            [screen addAttribute:TAName value:[NSNumber numberWithInt:currentAttribute.all] range:range];
            [self invalidateLine:curY];
            
            curX += [insert length];
            
#ifdef PRINT_INPUT
            printf("%s", charString.UTF8String);
#endif
        }
    }
    
    inIndex -= i;
}


-(void)resetScreen   // UI
{
    [self getLock];
    firstInvalidLine = INT_MAX;
    lastInvalidLine = -1;
    screenOffset = 0;
    curX = 0;
    curY = 0;
    topMargin = 0;
    bottomMargin = rowCount - 1;
    originWithinMargins = NO;
    autoWrap = YES;
    autoBackWrap = NO;
    autoReturnLineFeed = NO;
    cursorKeyAnsi = YES;
    keypadNormal = YES;
    isVT100 = YES;
    [self setContent];
	
	gSets[0] = 'B';
	gSets[1] = 'B';
	gSets[2] = 'B';
	gSets[3] = 'B';
    
    savedCurX = 0;
    savedCurY = 0;
    savedOriginWithinMargins = NO;
    savedAutoWrap = YES;
    savedAttribute.all = 0;
    // Implement also the other saved values from ESC 7.
    [lock unlock];
}


-(void)scrollBack:(int)repeat
{
    // Clip the repeat to the amount of scrollable rows.
    SInt32 scrollRowCount = bottomMargin - topMargin + 1;
    if (repeat > scrollRowCount)
    {
        repeat = scrollRowCount;
    }
    
    // Delete lines from the bottom of the scroll region.
    NSRange deleteRange;
    deleteRange.location = (bottomMargin + 1 - repeat) * columnCount;
    deleteRange.length = repeat * columnCount;
    [screen deleteCharactersInRange:deleteRange];
    
    // Insert blank lines at the top of the scroll region, if necessary.
    SInt32 insertIndex = topMargin * columnCount;
    for (int i = 0; i < repeat; i++)
    {
        [screen insertAttributedString:blankLine atIndex:insertIndex];
    }

	[self invalidateLine:topMargin];
	[self invalidateLine:bottomMargin];
}


-(void)scrollFeed:(int)repeat
{
    if (topMargin == 0 && bottomMargin == rowCount - 1 && isAlternate == NO)
    {
        // Normal scroll mode: simply add a line, the upper lines move into the back-scroll.
        if (repeat > rowCount)
        {
            repeat = rowCount;
        }
        [self addLine:repeat];
    }
    else
    {
        // Limited scroll mode: only a portion of the terminal screen is scrolling,
        // no lines are moving into the back-scroll.
        
        // Clip the repeat to the amount of scrollable rows.
        SInt32 scrollRowCount = bottomMargin - topMargin + 1;
        if (repeat > scrollRowCount)
        {
            repeat = scrollRowCount;
        }
        
        // Delete lines from the top of the scroll region.
        NSRange deleteRange;
        deleteRange.location = topMargin * columnCount;
        deleteRange.length = repeat * columnCount;
        [screen deleteCharactersInRange:deleteRange];
        
        // Insert blank lines at the bottom of the scroll region.
        SInt32 insertIndex = (bottomMargin + 1 - repeat) * columnCount;
        for (int i = 0; i < repeat; i++)
        {
            [screen insertAttributedString:blankLine atIndex:insertIndex];
        }
        
        [self invalidateLine:topMargin];
        [self invalidateLine:bottomMargin];
    }
}


-(void)setConnection:(id<VT100Connection>)newConnection   // UI
{
    [connection release];
    connection = newConnection;
    [connection retain];
    [connection setWidth:columnCount height:rowCount];
    [connection setDataDelegate:self];
}


-(void)setContent
{
    NSLayoutManager* layout = textView.layoutManager;
    NSMutableAttributedString* storage = layout.textStorage;
    
    // Count the number of lines in the view.
    int lineCount = 0;
    int glyphCount = (int)[layout numberOfGlyphs];
    int glyphIndex = 0;
    while (glyphIndex < glyphCount)
    {
        NSRange glyphRange;
        [layout lineFragmentRectForGlyphAtIndex:glyphIndex effectiveRange:&glyphRange];
        glyphIndex = (int)glyphRange.location + (int)glyphRange.length;
        lineCount++;
    }
    
    // Locate the line in the view that corresponds to the top line in the screen.
    if (lineCount <= rowCount)
    {
        screenOffset = 0;
        glyphIndex = 0;
    }
    else
    {
        screenOffset = lineCount - rowCount;
        glyphIndex = glyphCount - 1;
        NSRange glyphRange = NSMakeRange(0, 0);
        for (int i = 0; i < rowCount; i++)
        {
            [layout lineFragmentRectForGlyphAtIndex:glyphIndex effectiveRange:&glyphRange];
            glyphIndex = (int)glyphRange.location - 1;
        }
        glyphIndex = (int)glyphRange.location;
    }
    
    // Transfer lines from the view to the screen, and restore the cursor position.
    [screen deleteCharactersInRange:NSMakeRange(0, screen.length)];
    for (int i = 0; i < rowCount; i++)
    {
        if (i < lineCount)
        {
            NSRange glyphRange;
            [layout lineFragmentRectForGlyphAtIndex:glyphIndex effectiveRange:&glyphRange];
            NSRange range = [layout characterRangeForGlyphRange:glyphRange actualGlyphRange:NULL];
            
            if (savedCursorChar >= range.location && savedCursorChar < range.location + range.length)
            {
				[self invalidateLine:curY];
                curY = i + savedCursorDeltaY;
                if (curY < 0)
                {
                    curY = 0;
                }
                if (curY >= rowCount)
                {
                    curY = rowCount - 1;
                }
                
                curX = savedCursorChar - (int)range.location + savedCursorDeltaX;
                if (curX < 0)
                {
                    curX = 0;
                }
                if (curX >= columnCount)
                {
                    curX = columnCount - 1;
                }
				[self invalidateLine:curY];
            }
            
            if (range.length >= 2)
            {
                if ([storage.mutableString characterAtIndex:range.location + range.length - 2] == '\r')
                {
                    range.length -= 2;
                }
            }
            
            if (range.length > columnCount)
            {
                range.length = columnCount;
            }
            if (range.length > 0)
            {
                NSAttributedString* transfer = [storage attributedSubstringFromRange:range];
                [screen appendAttributedString:transfer];
            }
            if (range.length < columnCount)
            {
                NSAttributedString* blankString = [blankLine attributedSubstringFromRange:NSMakeRange(0, columnCount - range.length)];
                [screen appendAttributedString:blankString];
            }
            glyphIndex = (int)glyphRange.location + (int)glyphRange.length;
        }
        else
        {
            [screen appendAttributedString:blankLine];
        }
    }
}


-(void)setWidth:(int)newColumnCount height:(int)newRowCount   // UI
{
    [self getLock];
    columnCount = newColumnCount;
    rowCount = newRowCount;
    if (columnCount < 1)
    {
        columnCount = 1;
    }
    if (rowCount < 1)
    {
        rowCount = 1;
    }
    
    NSString* blankString = [@" " stringByPaddingToLength:columnCount withString:@" " startingAtIndex:0];
    [blankLine release];
    blankLine = [[NSAttributedString alloc] initWithString:blankString attributes:newLineAttributes];
    
    if (newColumnCount > tabStops.length)
    {
        UInt64 i = tabStops.length;
        tabStops.length = newColumnCount;
        for ( ; i < newColumnCount; i++)
        {
            ((char*)tabStops.mutableBytes)[i] = (i % 8 == 0 ? 1 : 0);
        }
    }
    
    [screen deleteCharactersInRange:NSMakeRange(0, screen.length)];
    
    if (connection != nil)
    {
        [connection setWidth:columnCount height:rowCount];
        [self setContent];
    }
    
    topMargin = 0;
    bottomMargin = rowCount - 1;
    savedCurX = 0;
    savedCurY = 0;
    [lock unlock];
}


-(void)setFontWithname:(NSString*)newFontName size:(CGFloat)newFontSize
{
	[normalFont release];
	normalFont = [NSFont fontWithName:newFontName size:newFontSize];

	NSFontManager* fontManager = [NSFontManager sharedFontManager];
	[boldFont release];
	boldFont = [fontManager convertFont:normalFont toHaveTrait:NSBoldFontMask];
	[boldFont retain];
	
	NSSize fontSize = [normalFont advancementForGlyph:'M'];
	fontWidth = fontSize.width;
	fontHeight = [textView.layoutManager defaultLineHeightForFont:normalFont];

	[newLineAttributes release];
	newLineAttributes = [NSDictionary dictionaryWithObjectsAndKeys:normalFont, NSFontAttributeName, paragraphStyle, NSParagraphStyleAttributeName, nil];
	[newLineAttributes retain];
	[blankChar release];
	blankChar = [[NSAttributedString alloc] initWithString:@" " attributes:newLineAttributes];
	[lineFeed release];
	lineFeed = [[NSAttributedString alloc] initWithString:@"\r\n" attributes:newLineAttributes];
	
	// Paste to text.
	NSMutableDictionary* dictionary = [NSMutableDictionary dictionaryWithDictionary:newLineAttributes];
	NSMutableAttributedString* terminalView = [textView.layoutManager textStorage];
	[terminalView setAttributes:dictionary range:NSMakeRange(0, terminalView.length)];
	[screen setAttributes:dictionary range:NSMakeRange(0, screen.length)];
	[self actualizeAttributesIn:[textView.layoutManager textStorage]];
	[self actualizeAttributesIn:screen];
}


-(instancetype)init:(NSTextView*)newTextView
{
    self = [super init];
    if (self != nil)
    {
        textView = newTextView;   // No retain because the text view owns this object.
        screen = [NSMutableAttributedString new];
        lock = [NSLock new];
        inIndex = 0;
        columnCount = 80;
        rowCount = 24;
        normalFont = [NSFont userFixedPitchFontOfSize:0];
        paragraphStyle = [[NSMutableParagraphStyle alloc] init];
        [paragraphStyle setParagraphStyle:[NSParagraphStyle defaultParagraphStyle]];
        [paragraphStyle setLineBreakMode:NSLineBreakByCharWrapping];
        [paragraphStyle setParagraphSpacing:0];
        newLineAttributes = [NSDictionary dictionaryWithObjectsAndKeys:normalFont, NSFontAttributeName, paragraphStyle, NSParagraphStyleAttributeName, nil];
        [newLineAttributes retain];
        blankChar = [[NSAttributedString alloc] initWithString:@" " attributes:newLineAttributes];
        lineFeed = [[NSAttributedString alloc] initWithString:@"\r\n" attributes:newLineAttributes];
        insert = [[NSMutableAttributedString alloc] init];
        tabStops = [[NSMutableData alloc] init];
        
        rowCount = 24;
        
        backColors[0] = [NSColor blackColor];   // Default background.
		backColors[1] = [NSColor blackColor];
		backColors[2] = [NSColor redColor];
		backColors[3] = [NSColor greenColor];
		backColors[4] = [NSColor yellowColor];
		backColors[5] = [NSColor blueColor];
		backColors[6] = [NSColor magentaColor];
		backColors[7] = [NSColor cyanColor];
		backColors[8] = [NSColor whiteColor];
		backColors[9] = [NSColor blackColor];
		backColors[10] = [NSColor redColor];
		backColors[11] = [NSColor greenColor];
		backColors[12] = [NSColor yellowColor];
		backColors[13] = [NSColor blueColor];
		backColors[14] = [NSColor magentaColor];
		backColors[15] = [NSColor cyanColor];
		backColors[16] = [NSColor whiteColor];
        
        textColors[0] = [NSColor whiteColor];   // Default foreground.
		textColors[1] = [NSColor blackColor];
		textColors[2] = [NSColor redColor];
		textColors[3] = [NSColor greenColor];
		textColors[4] = [NSColor yellowColor];
		textColors[5] = [NSColor blueColor];
		textColors[6] = [NSColor magentaColor];
		textColors[7] = [NSColor cyanColor];
		textColors[8] = [NSColor whiteColor];
		textColors[9] = [NSColor blackColor];
		textColors[10] = [NSColor redColor];
		textColors[11] = [NSColor greenColor];
		textColors[12] = [NSColor yellowColor];
		textColors[13] = [NSColor blueColor];
		textColors[14] = [NSColor magentaColor];
		textColors[15] = [NSColor cyanColor];
		textColors[16] = [NSColor whiteColor];
        
		cursorAttributes = [NSDictionary dictionaryWithObjectsAndKeys:[NSColor whiteColor], NSBackgroundColorAttributeName, [NSColor blackColor], NSForegroundColorAttributeName, nil];
		[cursorAttributes retain];

		NSFontManager* fontManager = [NSFontManager sharedFontManager];
        boldFont = [fontManager convertFont:normalFont toHaveTrait:NSBoldFontMask];
        [boldFont retain];

        NSSize fontSize = [normalFont advancementForGlyph:'M'];
        fontWidth = fontSize.width;
        fontHeight = [textView.layoutManager defaultLineHeightForFont:normalFont];
	}
    
    return self;
}


-(void)dealloc
{
    [connection release];
	[normalFont release];
    [boldFont release];
    [paragraphStyle release];
    [newLineAttributes release];
    [blankLine release];
    [blankChar release];
    [lineFeed release];
    [insert release];
    [tabStops release];
    [lock release];
    
    [super dealloc];
}


@end


