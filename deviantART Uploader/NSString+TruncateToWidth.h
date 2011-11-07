// Copyright © 1999-2011 deviantART Inc.

#import <Cocoa/Cocoa.h>


@interface NSString (TruncateToWidth)

- (NSString*)stringByTruncatingStringToWidth:(CGFloat)width withAttributes:(NSDictionary *)attributes;

@end
