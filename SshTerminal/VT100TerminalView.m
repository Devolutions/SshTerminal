//
//  SshTerminal.m
//  LibSshTest
//
//  Created by Denis Vincent on 2015-06-03.
//  Copyright (c) 2015 Denis Vincent. All rights reserved.
//

#import "VT100TerminalView.h"
#import "VT100Storage.h"

#ifdef DEBUG
//#define PRINT_INPUT 1
#endif

#define KEYPAD_ENTER 0x03

#define STORAGE_WIDTH (columnCount + 2)

#define TA_BOLD 0x01
#define TA_UNDERLINE 0x02
#define TA_BLINK 0x04
#define TA_INVERSE 0x08
#define TA_INVISIBLE 0x10

NSString* TAName = @"TerminalAttributeName";


@implementation VT100TerminalView

-(void)setConnection:(id<VT100Connection>)newConnection
{
    connection = newConnection;
    [connection setDataDelegate:self];
}


-(NSRect)cursorRect
{
    NSRange range = NSMakeRange(charTop + curY * STORAGE_WIDTH + curX, 1);
    NSRect rect = NSMakeRect(0, 0, 0, 0);;
    NSUInteger rectCount;
    NSRectArray rectarray = [self.layoutManager rectArrayForCharacterRange:range withinSelectedCharacterRange:range inTextContainer:self.textContainer rectCount:&rectCount];
    if (rectCount > 0)
    {
        rect = rectarray[0];
    }
    
    return rect;
}


-(void)setCursorVisible:(BOOL)visible
{
    if (visible != isCursorVisible)
    {
        isCursorVisible = visible;
        NSRect rect = [self cursorRect];
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
    
    NSRect rect = [self cursorRect];
    if (NSIsEmptyRect(rect) == NO)
    {
        [textColors[0] setFill];
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
        if ([theKey characterAtIndex:0] != 'v')
        {
            return;
        }
        NSPasteboard* pasteboard = [NSPasteboard generalPasteboard];
        NSArray* classes = [[NSArray alloc] initWithObjects:[NSString class], nil];
        NSDictionary* options = [NSDictionary dictionary];
        NSArray* copiedItems = [pasteboard readObjectsForClasses:classes options:options];
        if (copiedItems != nil)
        {
            for (int i = 0; i < copiedItems.count; i++)
            {
                NSString* string = [copiedItems objectAtIndex:i];
                const char* chars = [string UTF8String];
                [connection writeFrom:(const UInt8 *)chars length:(int)strlen(chars)];
            }
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
                if (keypadNormal == NO)
                {
                    sprintf(specialSequence, "\x1BOM");
                }
                else if (autoReturnLineFeed == NO)
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
                if (autoReturnLineFeed == YES)
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
                if ((theEvent.modifierFlags & NSNumericPadKeyMask) && keypadNormal == NO)
                {
                    sprintf(specialSequence, "\x1BO%c", keyCode - '0' + 'p');
                }
                break;
            }
                
            case '-':
            {
                if ((theEvent.modifierFlags & NSNumericPadKeyMask) && keypadNormal == NO)
                {
                    sprintf(specialSequence, "\x1BOm");
                }
                break;
            }
                
            case '.':
            {
                if ((theEvent.modifierFlags & NSNumericPadKeyMask) && keypadNormal == NO)
                {
                    sprintf(specialSequence, "\x1BOn");
                }
                break;
            }
                
            case '+':
            {
                if ((theEvent.modifierFlags & NSNumericPadKeyMask) && keypadNormal == NO)
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


-(void)addLine
{
    [self.textStorage appendAttributedString:lineFeed];
    [self.textStorage appendAttributedString:blankLine];
}


-(void)actualizeAttributes:(NSRange)actualizeRange
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
        [storage setAttributes:dictionary range:range];
    };
    
    [storage enumerateAttribute:TAName inRange:actualizeRange options:0 usingBlock:change];
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
        for (int i = 0; i < repeat; i++)
        {
            charTop += STORAGE_WIDTH;
            if (charTop + rowCount * STORAGE_WIDTH > [storage length])
            {
                [self addLine];
            }
        }
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
        deleteRange.location = charTop + topMargin * STORAGE_WIDTH;
        deleteRange.length = STORAGE_WIDTH;
        for (int i = 0; i < repeat; i++)
        {
            if (deleteRange.location >= [storage length])
            {
                break;
            }
            if (deleteRange.location + deleteRange.length > [storage length])
            {
                deleteRange.length = [storage length] - deleteRange.location;
            }
            [storage deleteCharactersInRange:deleteRange];
        }
        
        // Insert blank lines at the bottom of the scroll region, if necessary.
        SInt32 insertIndex = charTop + (bottomMargin + 1 - repeat) * STORAGE_WIDTH;
        if (insertIndex < [storage length])
        {
            for (int i = 0; i < repeat; i++)
            {
                [storage insertAttributedString:blankLine atIndex:insertIndex];
                [storage insertAttributedString:lineFeed atIndex:insertIndex + columnCount];
                insertIndex += STORAGE_WIDTH;
            }
        }
    }
}


-(void)scrollBack:(int)repeat
{
    // Clip the repeat to the amount of scrollable rows.
    SInt32 scrollRowCount = bottomMargin - topMargin + 1;
    if (repeat > scrollRowCount)
    {
        repeat = scrollRowCount;
    }
    
    // Delete lines from the bottom of the scroll region, if necessary.
    NSRange deleteRange;
    deleteRange.location = charTop + (bottomMargin + 1 - repeat) * STORAGE_WIDTH;
    deleteRange.length = STORAGE_WIDTH;
    for (int i = 0; i < repeat; i++)
    {
        if (deleteRange.location >= [storage length])
        {
            break;
        }
        if (deleteRange.location + deleteRange.length > [storage length])
        {
            deleteRange.length = [storage length] - deleteRange.location;
        }
        [storage deleteCharactersInRange:deleteRange];
    }
    
    // Insert blank lines at the top of the scroll region, if necessary.
    SInt32 insertIndex = charTop + topMargin * STORAGE_WIDTH;
    if (insertIndex < [storage length])
    {
        for (int i = 0; i < repeat; i++)
        {
            [storage insertAttributedString:blankLine atIndex:insertIndex];
            [storage insertAttributedString:lineFeed atIndex:insertIndex + columnCount];
            insertIndex += STORAGE_WIDTH;
        }
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


-(void)cursorDown:(int)repeat
{
    curY += repeat;
    if (curY > bottomMargin)
    {
        curY = bottomMargin;
    }
    
    UInt32 curPos = charTop + curY * STORAGE_WIDTH;
    while ( [storage length] < curPos)
    {
        [self addLine];
    }
}


-(void)cursorRight:(int)repeat
{
    curX += repeat;
    if (curX >= columnCount)
    {
        curX = columnCount - 1;
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


-(void)cursorToNextLine:(int)repeat
{
    curX = 0;
    [self cursorDown:repeat];
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
    
    UInt32 curPos = charTop + curY * STORAGE_WIDTH;
    while ( [storage length] < curPos)
    {
        [self addLine];
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
        NSRange range;
        range.location = charTop + curY * STORAGE_WIDTH + curX;
        NSAttributedString* movedString = [storage attributedSubstringFromRange:NSMakeRange(range.location, columnCount - curX - insertCount)];
        range.length = movedString.length;
        range.location += insertCount;
        [storage replaceCharactersInRange:range withAttributedString:movedString];
        NSAttributedString* blankString = [blankLine attributedSubstringFromRange:NSMakeRange(0, insertCount)];
        range.location -= insertCount;
        range.length = insertCount;
        [storage replaceCharactersInRange:range withAttributedString:blankString];
    }
}


-(void)deleteInLine:(int)arg
{
    NSRange range;
    if (arg == -1 || arg == 0)
    {
        // Blank from cursor inclusive to end of line.
        range.location = charTop + curY * STORAGE_WIDTH + curX;
        range.length = columnCount - curX;
        if (range.location < [storage length])
        {
            NSAttributedString* blankString = [blankLine attributedSubstringFromRange:NSMakeRange(0, range.length)];
            [storage replaceCharactersInRange:range withAttributedString:blankString];
        }
    }
    else if (arg == 1)
    {
        // Blank from begining of line to cursor inclusive.
        range.location = charTop + curY * STORAGE_WIDTH;
        range.length = curX + 1;
        if (range.location < [storage length])
        {
            NSAttributedString* blankString = [blankLine attributedSubstringFromRange:NSMakeRange(0, range.length)];
            [storage replaceCharactersInRange:range withAttributedString:blankString];
        }
    }
    else if (arg == 2)
    {
        // Blank whole line.
        range.location = charTop + curY * STORAGE_WIDTH;
        range.length = columnCount;
        if (range.location < [storage length])
        {
            [storage replaceCharactersInRange:range withAttributedString:blankLine];
        }
    }
}


-(void)deleteInScreen:(int)arg
{
    NSRange range;
    if (arg == -1 || arg == 0)
    {
        // Blank from cursor inclusive to end of screen.
        range.location = charTop + curY * STORAGE_WIDTH + curX;
        range.length = columnCount - curX;
        if (range.location < [storage length])
        {
            NSAttributedString* blankString = [blankLine attributedSubstringFromRange:NSMakeRange(0, range.length)];
            [storage replaceCharactersInRange:range withAttributedString:blankString];
            
            range.location = charTop + (curY + 1) * STORAGE_WIDTH;
            range.length = columnCount;
            while (range.location + range.length <= [storage length])
            {
                [storage replaceCharactersInRange:range withAttributedString:blankLine];
                range.location += STORAGE_WIDTH;
            }
        }
    }
    else if (arg == 1)
    {
        // Blank from begining of screen to cursor inclusive.
        range.location = charTop + curY * STORAGE_WIDTH;
        range.length = curX + 1;
        if (range.location < [storage length])
        {
            NSAttributedString* blankString = [blankLine attributedSubstringFromRange:NSMakeRange(0, range.length)];
            [storage replaceCharactersInRange:range withAttributedString:blankString];
        }

        range.location = charTop;
        range.length = columnCount;
        for (int i = 0; i < curY; i++)
        {
            if (range.location + range.length <= [storage length])
            {
                [storage replaceCharactersInRange:range withAttributedString:blankLine];
                range.location += STORAGE_WIDTH;
            }
            else
            {
                break;
            }
        }
    }
    else if (arg == 2)
    {
        // Blank whole screen, cursor does not move.
        for (int i = 0; i < viewRowCount; i++)
        {
            [self addLine];
        }
        charTop = (SInt32)[storage length] - STORAGE_WIDTH * viewRowCount + 2;
    }
    else if (arg == 3)
    {
        // Blank whole screen and back-scroll.
    }
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
    printf("%02X\r\n", c);
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
            if (deleteCount + curX > columnCount)
            {
                deleteCount = columnCount - curX;
            }
            
            if (deleteCount > 0)
            {
                NSRange moveRange;
                moveRange.location = charTop + curY * STORAGE_WIDTH + curX + deleteCount;
                moveRange.length = columnCount - curX - deleteCount;
                if (moveRange.length > 0)
                {
                    NSAttributedString* movedString = [storage attributedSubstringFromRange:moveRange];
                    moveRange.location -= deleteCount;
                    [storage replaceCharactersInRange:moveRange withAttributedString:movedString];
                    
                    NSAttributedString* blankString = [blankLine attributedSubstringFromRange:NSMakeRange(0, deleteCount)];
                    NSRange blankRange;
                    blankRange.location = charTop + curY * STORAGE_WIDTH + columnCount - deleteCount;
                    blankRange.length = deleteCount;
                    [storage replaceCharactersInRange:blankRange withAttributedString:blankString];
                }
            }
            
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
            if (deleteCount + curX > columnCount)
            {
                deleteCount = columnCount - curX;
            }
            
            if (deleteCount > 0)
            {
                NSRange range;
                range.location = charTop + curY * STORAGE_WIDTH + curX;
                range.length = deleteCount;
                NSAttributedString* blankString = [blankLine attributedSubstringFromRange:NSMakeRange(0, deleteCount)];
                [storage replaceCharactersInRange:range withAttributedString:blankString];
            }
            
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
                                    [self actualizeAttributes:NSMakeRange(0, [storage length])];
                                    self.backgroundColor = backColors[0];
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
                                [self actualizeAttributes:NSMakeRange(0, [storage length])];
                                self.backgroundColor = backColors[0];
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


-(void)alignTest
{
    NSString* testString = [@"E" stringByPaddingToLength:columnCount withString:@"E" startingAtIndex:0];
    NSAttributedString* testLine = [[NSAttributedString alloc] initWithString:testString attributes:newLineAttributes];
    
    NSRange range;
    range.location = charTop;
    range.length = columnCount;
    for (int i = 0; i < rowCount; i++)
    {
        if (range.location > [storage length])
        {
            [self addLine];
        }
        [storage replaceCharactersInRange:range withAttributedString:testLine];
        range.location += STORAGE_WIDTH;
    }
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


-(void)setColumnCount:(int)newCount
{
    columnCount = newCount;
    [connection setWidth:newCount];
    NSString* blankString = [@" " stringByPaddingToLength:columnCount withString:@" " startingAtIndex:0];
    blankLine = [[NSAttributedString alloc] initWithString:blankString attributes:newLineAttributes];
    
    NSSize containerSize = [self.textContainer containerSize];
    containerSize.width = blankLine.size.width + self.textContainer.lineFragmentPadding * 2;
    [self.textContainer setContainerSize:containerSize];
    NSSize size = self.frame.size;
    size.width = containerSize.width;
    [self setFrameSize:size];
    
    if (newCount > tabStops.length)
    {
        UInt64 i = tabStops.length;
        tabStops.length = newCount;
        for ( ; i < newCount; i++)
        {
            ((char*)tabStops.mutableBytes)[i] = (i % 8 == 0 ? 1 : 0);
        }
    }
}

-(void)setRowCountForHeight:(int)height
{
    int fontHeight = (int)([normalFont ascender] - [normalFont descender] + [normalFont leading] +0.5F);
    viewRowCount = height / fontHeight;
}


-(void)initScreen
{
    charTop = 0;
    curX = 0;
    curY = 0;
    topMargin = 0;
    bottomMargin = rowCount - 1;
    originWithinMargins = NO;
    autoWrap = YES;
    autoBackWrap = NO;
    autoReturnLineFeed = NO;
    keypadNormal = YES;
    isVT100 = YES;
    [storage setAttributedString:blankLine];
    
    savedCurX = 0;
    savedCurY = 0;
    savedOriginWithinMargins = NO;
    savedAutoWrap = YES;
    savedAttribute.all = 0;
    // Implement also the other saved values from ESC 7.
}


-(void)newDataAvailableIn:(UInt8*)buffer length:(int)size
{
    while (size > 0)
    {
        int copySize = (size > TERMINAL_BUFFER_SIZE - inIndex ? TERMINAL_BUFFER_SIZE - inIndex : size);
        memcpy(inBuffer + inIndex, buffer, copySize);
        inIndex += copySize;
        [self newDataAvailable];
        size -= copySize;
        buffer += copySize;
    }

    [self actualizeAttributes:NSMakeRange(charTop, [storage length] - charTop)];
    [self setSelectedRange:NSMakeRange(charTop + curY * STORAGE_WIDTH + curX, 0)];
    [self scrollRangeToVisible:NSMakeRange(charTop, [storage length] - charTop)];
}


-(void)newDataAvailable
{
    char charBuffer[2] = {0, 0};
    int i;
    //[storage beginEditing];
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
            range.location = charTop + curY * STORAGE_WIDTH + curX;
            range.length = [insert length];
            [insert setAttributes:newLineAttributes range:NSMakeRange(0, range.length)];
            while (range.location >= storage.length)
            {
                [self addLine];
            }
            if (insertMode == YES)
            {
                [self insertInLine:(int)range.length];
            }
            [storage replaceCharactersInRange:range withAttributedString:insert];
            [storage addAttribute:TAName value:[NSNumber numberWithInt:currentAttribute.all] range:range];
            
            curX += [insert length];
            
#ifdef PRINT_INPUT
            printf("%c", c);
#endif
        }
    }
    //[storage endEditing];
    
    inIndex -= i;
}

 
-(instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self != nil)
    {
        [self setVerticallyResizable:YES];
        [self setHorizontallyResizable:NO];
        [self setTextContainerInset:NSMakeSize(0, 0)];
        storage = [[VT100Storage alloc] init];
        [self.layoutManager replaceTextStorage:storage];
        [self.textContainer setWidthTracksTextView:NO];
        [self.textContainer setHeightTracksTextView:NO];
        [self.textContainer setLineFragmentPadding:2];
        inIndex = 0;
        columnCount = 120;
        isCursorVisible = NO;
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
        
        self.backgroundColor = backColors[0];
        
        NSFontManager* fontManager = [NSFontManager sharedFontManager];
        boldFont = [fontManager convertFont:normalFont toHaveTrait:NSBoldFontMask];
    }
    
    return self;
}


@end
