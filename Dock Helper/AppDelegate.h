// Copyright © 1999-2011 deviantART Inc.

#import <Cocoa/Cocoa.h>
#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#import <DeviantART/DA.h>

@interface AppDelegate : NSObject {
	NSDistributedNotificationCenter *globalNotificationCenter;
	NSFileManager *fileManager;
	NSUserDefaults *defaults;
	
	NSString *stashid;
	float progress;
	BOOL dontSendQuitMessage;
	
	IBOutlet NSView *iconView;
	IBOutlet NSProgressIndicator *iconProgressBar;
}

- (void) applicationDidFinishLaunching:(NSNotification*)notice;
- (void) updateDockTile:(NSTimer*)timer;
- (void) queueFileNames:(NSArray *)files;

- (IBAction) openStash:(id)sender;
- (IBAction) openH_elp:(id)sender;
- (IBAction) openPreferences:(id)sender;
- (IBAction) openUpdates:(id)sender;

@end
