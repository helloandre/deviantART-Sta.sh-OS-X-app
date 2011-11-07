// Copyright © 1999-2011 deviantART Inc.

#import <Cocoa/Cocoa.h>


@interface StatusView : NSView<NSMenuDelegate> { // NSDraggingDestination
	NSStatusItem *statusItem;
	BOOL isHighlighted;
	BOOL colored;
	BOOL uploading;
	BOOL dragging;
	BOOL offline;
}

@property (retain, nonatomic) NSStatusItem *statusItem;
@property BOOL colored;
@property BOOL uploading;
@property BOOL offline;

@end
