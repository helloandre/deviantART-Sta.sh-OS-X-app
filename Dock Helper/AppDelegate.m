// Copyright © 1999-2011 deviantART Inc.

#import "AppDelegate.h"
#import "JAProcessInfo.h"

@implementation AppDelegate

- (id) init {
	if (self = [super init]) {		
		fileManager = [[NSFileManager defaultManager] retain];
		
		// Listen to messages coming from the helper
		
		globalNotificationCenter = [NSDistributedNotificationCenter defaultCenter];
		
		[globalNotificationCenter addObserver:self selector:@selector(helperStartedHandler:) name:@"DAHelperStarted" object:nil];
		[globalNotificationCenter addObserver:self selector:@selector(helperStoppedHandler:) name:@"DAHelperStopped" object:nil];
		[globalNotificationCenter addObserver:self selector:@selector(uploadStarted:) name:@"DAHelperUploadStarted" object:nil];
		[globalNotificationCenter addObserver:self selector:@selector(uploadProgress:) name:@"DAHelperUploadProgress" object:nil];
		[globalNotificationCenter addObserver:self selector:@selector(uploadDone:) name:@"DAHelperUploadDone" object:nil];
		[globalNotificationCenter addObserver:self selector:@selector(uploadError:) name:@"DAHelperUploadError" object:nil];
		[globalNotificationCenter addObserver:self selector:@selector(uploadsRemaining:) name:@"DAHelperUploadsRemaining" object:nil];
		[globalNotificationCenter addObserver:self selector:@selector(uploadsDone:) name:@"DAHelperUploadsDone" object:nil];
		[globalNotificationCenter addObserver:self selector:@selector(loggedIn:) name:@"DAHelperLoggedIn" object:nil];
		[globalNotificationCenter addObserver:self selector:@selector(loggedOut:) name:@"DAHelperLoggedOut" object:nil];
		
		defaults = [[NSUserDefaults standardUserDefaults] retain];
	}
	
	return self;
}

- (void) dealloc {
	[fileManager release];
	[defaults release];
	
	[super dealloc];
}

- (void) applicationDidFinishLaunching:(NSNotification*)notice {
	[[NSApp dockTile] setContentView: iconView];
	[[NSApp dockTile] display];
	
	NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval: 0.1 target: self selector: @selector(updateDockTile:) userInfo: nil repeats: YES];
	[timer retain];
	
	JAProcessInfo *procInfo = [[JAProcessInfo alloc] init];
	[procInfo obtainFreshProcessList];
	
	if ([procInfo findProcessesWithName:@"deviantART Uploa"] < 1) {
		NSString* mainAppPath = [[NSWorkspace sharedWorkspace] absolutePathForAppBundleWithIdentifier: @"com.deviantart.desktopuploader"];
		[[NSWorkspace sharedWorkspace] launchApplication:mainAppPath showIcon: YES autolaunch: NO];
	}
	
	[procInfo release];
	
	// Claim back the focus in case the helper is already running
	[NSApp activateIgnoringOtherApps:YES];
	
	[globalNotificationCenter postNotificationName:@"DAHelperRefreshUploadInfo" object:nil userInfo:nil];
}

- (void) applicationWillTerminate:(NSNotification *)aNotification {
	if	(!dontSendQuitMessage) {
		[globalNotificationCenter postNotificationName:@"DAHelperShutdown" object:nil userInfo:nil];
	}
}

- (BOOL) applicationShouldHandleReopen:(NSApplication *)theApplication hasVisibleWindows:(BOOL)flag {
	CGEventRef ourEvent = CGEventCreate(NULL);
	CGPoint pt = CGEventGetLocation(ourEvent);
	
	CGEventRef mouseDownEv = CGEventCreateMouseEvent(NULL,kCGEventRightMouseDown,pt,kCGMouseButtonRight);
	CGEventPost (kCGHIDEventTap, mouseDownEv);
	
	CFRelease(ourEvent);
	CFRelease(mouseDownEv);
	
	return YES;
}

- (void) updateDockTile:(NSTimer*)timer {
	if (progress > 0.0) {
		[iconProgressBar setDoubleValue: progress];
		[iconProgressBar startAnimation: self];
	} else {
		[iconProgressBar stopAnimation: self];
	}
	[[NSApp dockTile] display];
}

- (BOOL) application:(NSApplication *)sender openFile:(NSString *)path {
    NSLog(@"openFile");
	NSMutableArray *files = [[NSMutableArray alloc] init];
	[files addObject:path];
	
	[self queueFileNames:files];
	
	[files release];
	
	return YES;
}

- (void) queueFileNames:(NSArray *)files {
	[files retain];
	BOOL isDir;
	
	NSEnumerator *e = [files objectEnumerator];
	NSString *newFileName;
	
	while (newFileName = [e nextObject]) {
		if ([fileManager fileExistsAtPath:newFileName isDirectory:&isDir] && isDir) {
			NSMutableArray *realsubpaths = [[NSMutableArray alloc] init];
			NSArray *subpaths = [fileManager subpathsAtPath:newFileName];
			NSEnumerator *en = [subpaths objectEnumerator];
			NSString *subpath;
			while (subpath = [en nextObject]) {
				[realsubpaths addObject:[NSString stringWithFormat:@"%@/%@", newFileName, subpath]];
			}
			
			[self queueFileNames: realsubpaths];
		} else {
			NSLog(@"Queueing file: %@", newFileName);
			[globalNotificationCenter postNotificationName:@"DAHelperQueueFileName" object:newFileName userInfo:nil];
		}
	}
	[files release];
}

// Notifications coming from the helper

- (void) helperStartedHandler:(NSNotification*)msg {
	// The helper has finished starting up, we can claim back the focus
	[NSApp activateIgnoringOtherApps:YES];
}

- (void) helperStoppedHandler:(NSNotification*)msg {
	// If the helper is closed, we close the app as well (because its uploading ability is taken away)
	dontSendQuitMessage = YES;
	[NSApp terminate:self];
}

- (void) uploadStarted:(NSNotification*)msg {

}

- (void) uploadProgress:(NSNotification*)msg {
	progress = [[msg object] floatValue];
}

- (void) uploadDone:(NSNotification*)msg {
	NSString *aStashid = [msg object];
	
	stashid = [aStashid retain];
}
- (void) uploadError:(NSNotification*)msg {

}

- (void) uploadsRemaining:(NSNotification*)msg {
	unsigned int filesLeft = [[msg object] intValue];
	
	[[NSApp dockTile] setBadgeLabel:[NSString stringWithFormat:@"%d", filesLeft]];
}

- (void) uploadsDone:(NSNotification*)msg {
	[[NSApp dockTile] setBadgeLabel:@""];
	progress = 0.0;
}

- (IBAction) openStash:(id)sender {
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://sta.sh"]];
}

- (IBAction) openH_elp:(id)sender {
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://help.deviantart.com/deviantart/stash/"]];
}

- (IBAction) openPreferences:(id)sender {
	[globalNotificationCenter postNotificationName:@"DAHelperShowPreferences" object:nil userInfo:nil];
}

- (IBAction) openUpdates:(id)sender {
	[globalNotificationCenter postNotificationName:@"DAHelperShowUpdates" object:nil userInfo:nil];
}

@end
