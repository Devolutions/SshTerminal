//
//  SshStorage.h
//  LibSshTest
//
//  Created by Denis Vincent on 2015-06-11.
//  Copyright (c) 2015 Denis Vincent. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface SshStorage : NSTextStorage
{
    NSMutableAttributedString* theString;
    BOOL isEditing;
}

@end
