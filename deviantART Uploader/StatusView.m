// Copyright © 1999-2011 deviantART Inc.

#import "StatusView.h"
#import "AppDelegate.h"


@implementation StatusView

- (void)dealloc {
    [statusItem release];
    [super dealloc];
}

- (NSDragOperation) draggingEntered:(id <NSDraggingInfo>)sender {
    dragging = YES;
	[self setNeedsDisplay:YES];
    
    NSPasteboard *pboard;
    NSDragOperation sourceDragMask;
    
    sourceDragMask = [sender draggingSourceOperationMask];
    pboard = [sender draggingPasteboard];
    
    if ( [[pboard types] containsObject:NSFilenamesPboardType] ) {
        if (sourceDragMask & NSDragOperationCopy) {
            return NSDragOperationCopy;
        }
    }
	
	return NSDragOperationNone;
}

- (void) draggingExited:(id <NSDraggingInfo>)sender {
	dragging = NO;
	[self setNeedsDisplay:YES];
}

- (BOOL) performDragOperation:(id <NSDraggingInfo>)sender {
    NSLog(@"dropped stuff on the icon");
	dragging = NO;
	[self setNeedsDisplay:YES];
	
	NSPasteboard *pboard;
    NSDragOperation sourceDragMask;
	
    sourceDragMask = [sender draggingSourceOperationMask];
    pboard = [sender draggingPasteboard];
	
    if ([[pboard types] containsObject:NSFilenamesPboardType]) {
        NSArray *files = [pboard propertyListForType:NSFilenamesPboardType];
		
        if (sourceDragMask & NSDragOperationLink) {
			AppDelegate *delegate = [NSApp delegate];
			
			[delegate queueFileNames:files fromDrag:YES];
        } else {
            NSLog(@"Drop it");
        }
    }
	
	return YES;
}

- (void) mouseDown:(NSEvent *)event {
    [[statusItem menu] setDelegate:self];
    [statusItem popUpStatusItemMenu:[statusItem menu]];

	[self setNeedsDisplay:YES];
}

- (void) rightMouseDown:(NSEvent *)event {
    [self mouseDown:event];
}

- (void) menuWillOpen:(NSMenu *)menu {
    isHighlighted = YES;
    [self setNeedsDisplay:YES];
}

- (void) menuDidClose:(NSMenu *)menu {
    isHighlighted = NO;
    [menu setDelegate:nil];   
    [self setNeedsDisplay:YES];
}

- (void) drawRect:(NSRect)rect {
    [statusItem drawStatusBarBackgroundInRect:[self bounds] withHighlight:isHighlighted];
	
	NSImage *image;
	NSRect rectangle = NSMakeRect(0,0,16,17);
	
	if (offline) {
		image = [NSImage imageNamed:@"stash-status-offline.tif"];
	} else {
		if (isHighlighted) {
			image = [NSImage imageNamed:@"stash-status-click.tif"];
		} else {
			if (uploading) {
				image = [NSImage imageNamed:@"stash-status-uploading.tif"];
				rectangle = NSMakeRect(0,0,21,17);
			} else if (dragging) {
				image = [NSImage imageNamed:@"stash-status-busy.tif"];				  
			} else {
				if (colored) {
					image = [NSImage imageNamed:@"stash-status-idle-color.tif"];
				} else {
					image = [NSImage imageNamed:@"stash-status-idle.tif"];
				}
			}
		}
	}
	
	[image drawAtPoint:NSMakePoint(5, 2) fromRect:rectangle operation:NSCompositeSourceOver fraction:1.0]; 
}

@synthesize statusItem;
@synthesize colored;
@synthesize uploading;
@synthesize offline;

@end
