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


@implementation VT100ScreenBuffer

@synthesize cursorKeyAnsi;
@synthesize keypadNormal;
@synthesize autoReturnLineFeed;
@synthesize fontHeight;
@synthesize fontWidth;


-(NSColor*)backgroundColor
{
    return backColors[0];
}


-(void)actualizeAttributesIn:(NSMutableAttributedString*)string
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
    
    [string enumerateAttribute:TAName inRange:NSMakeRange(0, string.length) options:0 usingBlock:change];
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
        firstInvalidLine--;
    }
    else
    {
        firstInvalidLine = lastInvalidLine;
    }
    screenOffset++;
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
}


-(void)cursorDown:(int)repeat
{
    curY += repeat;
    if (curY > bottomMargin)
    {
        curY = bottomMargin;
    }
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


-(void)cursorRight:(int)repeat
{
    curX += repeat;
    if (curX >= columnCount)
    {
        curX = columnCount - 1;
    }
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
}


-(void)cursorUp:(int)repeat
{
    curY -= repeat;
    if (curY < topMargin)
    {
        curY = topMargin;
    }
}


-(void)cursorToRow:(int)row column:(int)col
{
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
}


-(void)deleteInLine:(int)arg
{
    NSRange range;
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
    [self invalidateLine:curY];
}


-(void)deleteInScreen:(int)arg
{
    NSRange range;
    range.length = columnCount;
    if (arg == -1 || arg == 0)
    {
        // Blank from cursor inclusive to end of screen.
        [self deleteInLine:0];   // Delete from cursor to end of line.
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
        [self deleteInLine:0];   // Delete from beginning of line to cursor inclusive.
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
        NSAttributedString* blankString = [blankLine attributedSubstringFromRange:NSMakeRange(0, moveCount)];
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
                    *escIndex = i - 1;
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
                    *escIndex = i - 1;
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
                    *escIndex =  - 1i;
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
                    *escIndex = i - 1;
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
                else if (j < i)
                {
                    modifier = inBuffer[j];
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
                *escIndex = i + 1;
            }
        }
        else if (c == ')')
        {
            if (i + 1 < inIndex)
            {
                complete = YES;
                *escIndex = i + 1;
            }
        }
        else if (c == '*')
        {
            if (i + 1 < inIndex)
            {
                complete = YES;
                *escIndex = i + 1;
            }
        }
        else if (c == '+')
        {
            if (i + 1 < inIndex)
            {
                complete = YES;
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
                    curX = savedCurX;
                    curY = savedCurY;
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
                    /*
                     case 'I':
                     {
                     // VT52 reverse line feed.
                     [self scrollBack:1];
                     break;
                     }
                     */
                case 'J':
                {
                    // VT52 delete from cursor to end of screen.
                    [self deleteInScreen:0];
                    break;
                }
                    
                case 'K':
                {
                    // VT52 delete from cursor to end of line.
                    [self deleteInLine:0];
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
        printf("(ESC %c)\r\n", c);
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
                    curX = columnCount - 1;
                    if (curY == topMargin)
                    {
                        [self scrollBack:1];
                    }
                    else
                    {
                        curY--;
                    }
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
            }
            break;
        }
    }
    
#ifdef PRINT_INPUT
    printf(" %02X ", c);
    if (c == '\n')
    {
        printf("\r\n");
    }
#endif
}


-(void)executeCsiCommand:(char)command withModifier:(char)modifier argValues:(int*)args argCount:(int)argCount
{
#ifdef PRINT_INPUT
    printf("([%c", command);
    for (int i = 0; i < argCount; i++)
    {
        printf(", %d", args[i]);
    }
    printf(")");
#endif
    
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
            [self deleteInLine:args[0]];
            break;
        }
            
        case 'L':
        {
            // Insert blank lines in screen after the current line (lines after the insterted lines are moved down).
            SInt32 insertCount = (args[0] < 0 ? 0 : args[0]);
            if (curY >= topMargin && curY < bottomMargin && insertCount > 0)
            {
                SInt32 savedMargin = topMargin;
                topMargin = curY + 1;
                [self scrollFeed:insertCount];
                topMargin = savedMargin;
            }
            
            break;
        }
            
        case 'M':
        {
            // Delete lines in screen after the current line (lines after the deleted lines are moved up).
            int deleteCount = (args[0] >= 0 ? args[0] : 1);
            if (curY >= topMargin && curY < bottomMargin && deleteCount > 0)
            {
                SInt32 savedMargin = topMargin;
                topMargin = curY + 1;
                [self scrollBack:deleteCount];
                topMargin = savedMargin;
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
            curY = (args[0] > 0 ? args[0] - 1 : 0);
            if (curY >= rowCount)
            {
                curY = rowCount - 1;
            }
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
                    currentAttribute.textColor = arg - 89;
                    continue;
                }
                if (arg >= 100 && arg <= 107)
                {
                    currentAttribute.backColor = arg - 99;
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
        int glyphCount = [layout numberOfGlyphs];
        int glyphIndex = 0;
        while (glyphIndex < glyphCount)
        {
            NSRange glyphRange;
            [layout lineFragmentRectForGlyphAtIndex:glyphIndex effectiveRange:&glyphRange];
            glyphIndex = glyphRange.location + glyphRange.length;
            if (lineCount == screenOffset)
            {
                screenTopGlyph = glyphRange.location;
            }
            if (lineCount == updateLine)
            {
                updateLineStart = [layout characterIndexForGlyphAtIndex:glyphRange.location];
            }
            lineCount++;
        }
        if (lineCount == 0)
        {
            lineCount = 1;
        }
        
        // Delete from the text view the part that needs updating.
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
        else {
            lastInvalidLine = rowCount - 1;
        }
        
        [storage beginEditing];
        for (int l = firstInvalidLine; l <= lastInvalidLine; l++)
        {
            int lineStart = l * columnCount;
            NSAttributedString* screenLine = [screen attributedSubstringFromRange:NSMakeRange(lineStart, columnCount)];
            [storage appendAttributedString:screenLine];
            
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
        glyphCount = [layout numberOfGlyphs];
        int line = 0;
        while (glyphIndex < glyphCount)
        {
            NSRange glyphRange;
            [layout lineFragmentRectForGlyphAtIndex:glyphIndex effectiveRange:&glyphRange];
            glyphIndex = glyphRange.location + glyphRange.length;
            if (line == curY)
            {
                int lineStart = [layout characterIndexForGlyphAtIndex:glyphRange.location];
                int lineEnd = [layout characterIndexForGlyphAtIndex:glyphRange.location + glyphRange.length];
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
            savedCursorChar = storage.length;
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
    NSRect previousRect = [self cursorRect];
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
    NSRect newRect = [self cursorRect];
    if (previousRect.origin.x != newRect.origin.x || previousRect.origin.y != newRect.origin.y)
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            [textView setNeedsDisplayInRect:previousRect];
            [textView setNeedsDisplayInRect:newRect];
        });
    }
    [lock unlock];
}


-(void)newDataAvailable
{
    char charBuffer[2] = {0, 0};
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
                    }
                    else
                    {
                        [self cursorDown:1];
                        curX = 0;
                    }
                }
                else
                {
                    curX = columnCount - 1;
                }
            }
            
            charBuffer[0] = c;
            [insert.mutableString setString:[NSString stringWithCString:charBuffer encoding:NSISOLatin1StringEncoding]];
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
            printf("%c", c);
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
    /*[screen deleteCharactersInRange:NSMakeRange(0, screen.length)];
    for (int i = 0; i < rowCount; i++)
    {
        [screen appendAttributedString:blankLine];
    }*/
    
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
}


-(void)scrollFeed:(int)repeat
{
    if (topMargin == 0 && bottomMargin == rowCount - 1)
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
    int glyphCount = [layout numberOfGlyphs];
    int glyphIndex = 0;
    while (glyphIndex < glyphCount)
    {
        NSRange glyphRange;
        [layout lineFragmentRectForGlyphAtIndex:glyphIndex effectiveRange:&glyphRange];
        glyphIndex = glyphRange.location + glyphRange.length;
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
        NSRange glyphRange;
        for (int i = 0; i < rowCount; i++)
        {
            [layout lineFragmentRectForGlyphAtIndex:glyphIndex effectiveRange:&glyphRange];
            glyphIndex = glyphRange.location - 1;
        }
        glyphIndex = glyphRange.location;
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
                curY = i + savedCursorDeltaY;
                if (curY < 0)
                {
                    curY = 0;
                }
                if (curY >= rowCount)
                {
                    curY = rowCount - 1;
                }
                
                curX = savedCursorChar - range.location + savedCursorDeltaX;
                if (curX < 0)
                {
                    curX = 0;
                }
                if (curX >= columnCount)
                {
                    curX = columnCount - 1;
                }
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
            glyphIndex = glyphRange.location + glyphRange.length;
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
        
        backColors[0] = [NSColor blackColor];
        backColors[1] = [NSColor blackColor];
        backColors[2] = [NSColor redColor];
        backColors[3] = [NSColor greenColor];
        backColors[4] = [NSColor yellowColor];
        backColors[5] = [NSColor blueColor];
        backColors[6] = [NSColor magentaColor];
        backColors[7] = [NSColor cyanColor];
        backColors[8] = [NSColor whiteColor];
        
        textColors[0] = [NSColor whiteColor];
        textColors[1] = [NSColor blackColor];
        textColors[2] = [NSColor redColor];
        textColors[3] = [NSColor greenColor];
        textColors[4] = [NSColor yellowColor];
        textColors[5] = [NSColor blueColor];
        textColors[6] = [NSColor magentaColor];
        textColors[7] = [NSColor cyanColor];
        textColors[8] = [NSColor whiteColor];
        
        NSFontManager* fontManager = [NSFontManager sharedFontManager];
        boldFont = [fontManager convertFont:normalFont toHaveTrait:NSBoldFontMask];
        [boldFont retain];

        NSSize fontSize = [normalFont advancementForGlyph:'M'];
        fontWidth = fontSize.width;
        fontHeight = [textView.layoutManager defaultLineHeightForFont:normalFont];;
}
    
    return self;
}


-(void)dealloc
{
    [connection release];
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


