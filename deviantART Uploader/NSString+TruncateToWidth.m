// Copyright © 1999-2011 deviantART Inc.

#import "NSString+TruncateToWidth.h"


@implementation NSString (TruncateToWidth)

- (NSString*)stringByTruncatingStringToWidth:(CGFloat)width withAttributes:(NSDictionary *)attributes {
    NSMutableString *resultString = [[self mutableCopy] autorelease];
    NSRange range = {resultString.length-1, 1};
	
	BOOL truncated;
	
    while ([resultString sizeWithAttributes:attributes].width > width) {
        [resultString deleteCharactersInRange:range];
        range.location--;
		truncated = YES;
    }
	
	if (truncated) {
		[resultString replaceCharactersInRange:range withString:@"…"];
	}
	
    return resultString;
}

@end
