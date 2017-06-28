//
//  SyntaxColoringItem.m
//  SshTerminal
//
//  Created by Laurent Pepin on 2017-06-23.
//  Copyright © 2017 Denis Vincent. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SyntaxColoringItem.h"

@implementation SyntaxColoringItem

@synthesize keyword;
@synthesize keywordLen;
@synthesize backColor;
@synthesize textColor;
@synthesize isCompleteWord;
@synthesize isCaseSensitive;
@synthesize isUnderlined;
@synthesize isEnabled;

-(void)dealloc
{
	[keyword release];
	[super dealloc];
}

@end
