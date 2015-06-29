//
//  SshStorage.m
//  LibSshTest
//
//  Created by Denis Vincent on 2015-06-11.
//  Copyright (c) 2015 Denis Vincent. All rights reserved.
//

#import "SshStorage.h"

@implementation SshStorage

-(NSString*)string
{
    return [theString string];
}


-(NSDictionary*)attributesAtIndex:(NSUInteger)location effectiveRange:(NSRangePointer)range
{
    return [theString attributesAtIndex:location effectiveRange:range];
}


-(void)replaceCharactersInRange:(NSRange)range withString:(NSString *)str
{
    [theString replaceCharactersInRange:range withString:str];
    [self edited:NSTextStorageEditedCharacters range:range changeInLength:[str length] - range.length];
}


-(void)setAttributes:(NSDictionary *)attrs range:(NSRange)range
{
    [theString setAttributes:attrs range:range];
    [self edited:NSTextStorageEditedAttributes range:range changeInLength:0];
}


-(void)beginEditing
{
    if (isEditing == NO)
    {
        [super beginEditing];
        isEditing = YES;
    }
}


-(void)endEditing
{
    if (isEditing == YES && [self editedMask] != 0)
    {
        [super endEditing];
        isEditing = NO;
    }
}


-(SshStorage*)init
{
    self = [super init];
    if (self != nil)
    {
        theString = [[NSMutableAttributedString alloc] init];
        isEditing = NO;
    }
    
    return self;
}


@end
