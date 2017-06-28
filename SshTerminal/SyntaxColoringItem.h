//
//  SyntaxColoringItem.h
//  SshTerminal
//
//  Created by Laurent Pepin on 2017-06-23.
//  Copyright © 2017 Denis Vincent. All rights reserved.
//

#ifndef SyntaxColoringItem_h
#define SyntaxColoringItem_h

#import <Cocoa/Cocoa.h>

@interface SyntaxColoringItem : NSObject
{
	NSString* keyword;
	int keywordLen;
	int backColor;
	int textColor;
	BOOL isCompleteWord;
	BOOL isCaseSensitive;
	BOOL isUnderlined;
	BOOL isEnabled;
}

@property(copy,nonatomic)NSString* keyword;
@property(assign)int keywordLen;
@property(assign)int backColor;
@property(assign)int textColor;
@property(assign)BOOL isCompleteWord;
@property(assign)BOOL isCaseSensitive;
@property(assign)BOOL isUnderlined;
@property(assign)BOOL isEnabled;

-(void)dealloc;

@end

#endif /* SyntaxColoringItem_h */
