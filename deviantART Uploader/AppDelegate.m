// Copyright © 1999-2011 deviantART Inc.

#import "AppDelegate.h"
#import "JAProcessInfo.h"
#import "NSString+TruncateToWidth.h"
#import "Reachability.h"

/* OAuth2Credentials.h isn't provided as part of the source code, as it contains private OAuth2 
 credentials that shouldn't be published. The header defines OAUTH2_CLIENT_ID and OAUTH2_CLIENT_SECRET */
#import "OAuth2Credentials.h"

@implementation AppDelegate

+ (void) addToLoginItems:(NSURL *)itemURL enabled:(BOOL)enabled {
    LSSharedFileListItemRef existingItem = NULL;
	
    LSSharedFileListRef loginItems = LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);
    if (loginItems) {
        UInt32 seed = 0U;
        NSArray *currentLoginItems = [NSMakeCollectable(LSSharedFileListCopySnapshot(loginItems, &seed)) autorelease];
        for (id itemObject in currentLoginItems) {
            LSSharedFileListItemRef item = (LSSharedFileListItemRef)itemObject;
			
            UInt32 resolutionFlags = kLSSharedFileListNoUserInteraction | kLSSharedFileListDoNotMountVolumes;
            CFURLRef URL = NULL;
            OSStatus err = LSSharedFileListItemResolve(item, resolutionFlags, &URL, /*outRef*/ NULL);
            if (err == noErr) {
                Boolean foundIt = CFEqual(URL, itemURL);
                CFRelease(URL);
				
                if (foundIt) {
                    existingItem = item;
                    break;
                }
            }
        }
		
        if (enabled && (existingItem == NULL)) {
            LSSharedFileListInsertItemURL(loginItems, kLSSharedFileListItemLast,
                                          NULL, NULL, (CFURLRef)itemURL, NULL, NULL);
			
        } else if (!enabled && (existingItem != NULL))
            LSSharedFileListItemRemove(loginItems, existingItem);
		
        CFRelease(loginItems);
    }       
}

- (id) init {
	if (self = [super init]) {
        fileManager = [[NSFileManager defaultManager] retain];
        
		updater = [SUUpdater updaterForBundle:[NSBundle bundleForClass:[self class]]];
		[updater setDelegate:self];
		
		// Add itself to login items
		
		[AppDelegate addToLoginItems:[NSURL fileURLWithPath:[[NSBundle mainBundle] bundlePath]] enabled:YES];
		
		dAStashUploader = [[DAStashUploader alloc] initWithClientID:OAUTH2_CLIENT_ID clientSecret:OAUTH2_CLIENT_SECRET delegate:self];
		
		defaults = [[NSUserDefaults standardUserDefaults] retain];
		
		// Reload previous file lists from defaults
		
		recentlyUploadedList = [[defaults arrayForKey:@"recentlyUploadedList"] mutableCopy];
		
		if (recentlyUploadedList == nil) {
			recentlyUploadedList = [[NSMutableArray alloc] init];
		}
		
		uploadFileNames = [[NSMutableDictionary alloc] init];
		
		// Listen to notifications coming from the main app
		
		globalNotificationCenter = [NSDistributedNotificationCenter defaultCenter];
		
		[globalNotificationCenter addObserver:self selector:@selector(queueFileName:) name:@"DAHelperQueueFileName" object:nil];
		[globalNotificationCenter addObserver:self selector:@selector(refreshUploadInfo:) name:@"DAHelperRefreshUploadInfo" object:nil];
		[globalNotificationCenter addObserver:self selector:@selector(shutdown:) name:@"DAHelperShutdown" object:nil];
		[globalNotificationCenter addObserver:self selector:@selector(openPreferences:) name:@"DAHelperShowPreferences" object:nil];
		[globalNotificationCenter addObserver:self selector:@selector(openUpdates:) name:@"DAHelperShowUpdates" object:nil];
		
		// Observe message that the share workspace sends after launching another app
		[[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector:@selector(mainAppLaunched:) name:NSWorkspaceDidLaunchApplicationNotification object:nil];
        
        // Observe screenshots
        
        metadataQuery = [[NSMetadataQuery alloc] init];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(metadataQueryUpdated:) name:NSMetadataQueryDidUpdateNotification object:metadataQuery];
        
        [metadataQuery setDelegate:self];
        
        NSString *screenshotsPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Desktop"];
        
        NSDictionary *appleDefaults = [[NSUserDefaults standardUserDefaults] persistentDomainForName:@"com.apple.screencapture"];
        
        if ([appleDefaults valueForKey:@"location"] != nil) {
            screenshotsPath = [appleDefaults valueForKey:@"location"];
        }
        
        NSLog(@"Listening for screenshots at: %@", screenshotsPath);
        
        [metadataQuery setSearchScopes:[NSArray arrayWithObjects:screenshotsPath,nil]];
        [metadataQuery setPredicate:[NSPredicate predicateWithFormat:@"kMDItemIsScreenCapture = 1"]];
        [metadataQuery startQuery];
        
        screenshotsToUpload = [[NSMutableDictionary alloc] init];
        
        // Reachability
        
        [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(reachabilityChanged:) name: kReachabilityChangedNotification object: nil];
        
        hostReach = [[Reachability reachabilityWithHostName: @"www.deviantart.com"] retain];
        [hostReach startNotifier];
	}
	
	return self;
}
 
- (void) dealloc {
	[recentlyUploadedList release];
	[uploadFileNames release];
	[lastFileName release];
	[globalNotificationCenter release];
	[defaults release];
	[dAStashUploader release];
	[statusItem release];
	[fileManager release];
    [metadataQuery stopQuery];
    [metadataQuery setDelegate:nil];
    [metadataQuery release];
    [screenshotsToUpload release];
    [hostReach release];
	
    [super dealloc];
}

- (void) applicationDidFinishLaunching:(NSNotification*) notice {
    // Lion doesn't like the way we use the Dock icon, it's all slow, hangs and sometimes just ignores drags :( until this can be figured out, disable the dock icon feature in anything > leopard
    BOOL isLeopard = [self isLeopard];
    
	statusItem = [[[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength] retain];
	
	if ([defaults boolForKey:@"isStatusIconColored"]) {
		statusView.colored = YES;
		[statusView	setNeedsDisplay:YES];
		[colorSwitch setState:NSOnState];
	}
    
    if (![defaults boolForKey:@"areScreenshotsNotUploaded"]) {
		[screenshotsSwitch setState:NSOnState];
        [deleteScreenshotsSwitch setEnabled:YES];
	} else {
        [deleteScreenshotsSwitch setEnabled:NO];
    }
    
    if ([defaults boolForKey:@"areScreenshotsDeletedAfterUpload"]) {
		[deleteScreenshotsSwitch setState:NSOnState];
	}
	
	if (isLeopard && [defaults boolForKey:@"isDockIconVisible"]) {
		JAProcessInfo *procInfo = [[JAProcessInfo alloc] init];
		[procInfo obtainFreshProcessList];
		
		if ([procInfo findProcessesWithName:@"deviantART Sta.s"] < 1) {
			NSString *dockHelperPath = [NSString stringWithFormat:@"%@/Contents/Resources/DeviantART Sta.sh Uploader.app", [[NSBundle mainBundle] bundlePath]];
			[[NSWorkspace sharedWorkspace] launchApplication:dockHelperPath showIcon: YES autolaunch: NO];
		}
	}
	
	[statusView registerForDraggedTypes:[NSArray arrayWithObjects: NSFilenamesPboardType, nil]];
	statusView.statusItem = statusItem;
	
	NSImage *statusImage = [NSImage imageNamed:@"stash-status-empty.tif"];
	[statusItem setImage:statusImage]; // We still need to specify the image, eventhough it's replaced by the view
	[statusItem setMenu: statusMenu];
	[statusItem setView: statusView];
		
	if (!isLeopard && [defaults boolForKey:@"isStatusIconHidden"]) {
		[statusView setHidden:YES];
	}
    
    if (isLeopard) {
        if ([defaults boolForKey:@"isDockIconVisible"] && ![defaults boolForKey:@"isStatusIconHidden"]) {
            [iconMenu selectItem:bothIcons];
        } else if ([defaults boolForKey:@"isDockIconVisible"]) {
            [iconMenu selectItem:dockIconOnly];
        }     
    } else {
        [iconMenu setHidden:TRUE];
    }
	
	[globalNotificationCenter postNotificationName:@"DAHelperStarted" object:nil userInfo:nil];
	
	originalMenuCount = [statusMenu numberOfItems];
	
	if ([recentlyUploadedList count] > 0) {
		NSEnumerator *e = [recentlyUploadedList objectEnumerator];
		NSDictionary *deviationInfo;
		
		while (deviationInfo = [e nextObject]) {
			[self addItemToStatusMenu:[deviationInfo objectForKey:@"fileName"] withURL:[deviationInfo objectForKey:@"url"]];
		}
	}
	
	if ([dAStashUploader isLoggedIn]) {
		[self loggedin];
	} else {
		[self loggedout];
	}
}

- (void) applicationWillTerminate:(NSNotification *)aNotification {
	[self persistLists];
	
	if (!dontShutdownMainApp) {
		[globalNotificationCenter postNotificationName:@"DAHelperStopped" object:nil userInfo:nil];
	}
}

- (void) persistLists {
	[defaults setObject:recentlyUploadedList forKey:@"recentlyUploadedList"];
}

- (void) queueFileNames:(NSArray *)files fromDrag:(BOOL)fromDrag {
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
			
			[self queueFileNames: realsubpaths fromDrag:fromDrag];
		} else {
			[uploadFileNames setValue:newFileName forKey: newFileName];
			[dAStashUploader queueFileName:newFileName folder:@"Desktop Uploads"];
		}
	}
	[files release];
}

- (void) refreshUploadCount {
	NSString *title;

	if (localUploadCount == 0) {
		title = [NSString stringWithFormat:@"All files up to date"];
	} else if (localUploadCount == 1) {
		title = [NSString stringWithFormat:@"%d file uploading", localUploadCount];
	} else {
		title = [NSString stringWithFormat:@"%d files uploading", localUploadCount];
	}
	
	[uploadStatus setTitle:title];
	[statusView setToolTip:title];
}

- (void) addItemToStatusMenu:(NSString*)title withURL:(NSString*)url {
	NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
								[NSColor blackColor], NSForegroundColorAttributeName, 
								[NSFont fontWithName:@"Lucida Grande" size:11.0], NSFontAttributeName, nil];	
	
	NSString *truncatedTitle = [title stringByTruncatingStringToWidth:165.0 withAttributes: attributes];
	
	NSMenuItem *menuItem = [[[NSMenuItem alloc] initWithTitle:truncatedTitle action:@selector(openLink:) keyEquivalent:@""] autorelease];

	NSAttributedString *attributedTitle = [[[NSAttributedString alloc] initWithString:truncatedTitle attributes:attributes] autorelease];
	
	[menuItem setAttributedTitle:attributedTitle];
	[menuItem setRepresentedObject:url];
	
	if ([statusMenu numberOfItems] == originalMenuCount) {
		[statusMenu insertItem:[NSMenuItem separatorItem] atIndex:2];
	}
	[statusMenu insertItem:menuItem atIndex:2];
	
	if ([statusMenu numberOfItems] > originalMenuCount + 11) {
		[statusMenu removeItemAtIndex:12];
	}
}

- (void) openLink:(id)sender {
	NSMenuItem *menuItem = sender;
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:[menuItem representedObject]]];
}

// DAStashUploaderDelegate protocol

- (void) uploadStarted:(NSString*)fileName {
	[globalNotificationCenter postNotificationName:@"DAHelperUploadStarted" object:fileName userInfo:nil];
	lastFileName = fileName;
	statusView.uploading = YES;
	[statusView setNeedsDisplay:YES];
}

- (void) uploadProgress:(float)newProgress {
	[globalNotificationCenter postNotificationName:@"DAHelperUploadProgress" object:[NSString stringWithFormat:@"%f", newProgress] userInfo:nil];
	lastProgress = newProgress;
}

- (void) uploadDone:(NSInteger)aStashid folderId: (NSInteger)aFolderId {
    NSLog(@"Deviation URL received: %ld", aStashid);
    
	[globalNotificationCenter postNotificationName:@"DAHelperUploadDone" object:[NSString stringWithFormat: @"%d", aStashid] userInfo:nil];
	
	// Get the fav.me link and send it to the pasteboard
	
	NSString *deviationURL = [DAUtils deviationURL:aStashid];
	
	NSPasteboard *generalPasteboard = [NSPasteboard generalPasteboard];
	[generalPasteboard declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
	[generalPasteboard clearContents];
	[generalPasteboard setString:deviationURL forType:NSStringPboardType];
    
    if ([defaults boolForKey:@"areScreenshotsDeletedAfterUpload"] && [screenshotsToUpload valueForKey:lastFileName] != nil) {
        NSError *err = nil;
        [fileManager removeItemAtPath:lastFileName error:&err];
    }
	
	NSString *fileNameOnly = [lastFileName lastPathComponent];
	
	// Add the last file uploaded to the status menu
	
	[self addItemToStatusMenu:fileNameOnly withURL:deviationURL];
	
	NSMutableDictionary *deviationInfo = [[[NSMutableDictionary alloc] init] autorelease];
	[deviationInfo setObject:fileNameOnly forKey:@"fileName"];
	[deviationInfo setObject:deviationURL forKey:@"url"];
	
	[recentlyUploadedList addObject:deviationInfo];
	if ([recentlyUploadedList count] > 10) {
		[recentlyUploadedList removeObjectAtIndex:0];
	}
	
	[self persistLists];
}

- (void) uploadError:(NSString*)errorHuman {
	[globalNotificationCenter postNotificationName:@"DAHelperUploadError" object:errorHuman userInfo:nil];
}

- (void) uploadsRemaining:(unsigned int)filesLeft total:(unsigned int)total {
	[globalNotificationCenter postNotificationName:@"DAHelperUploadsRemaining" object:[NSString stringWithFormat:@"%d", filesLeft] userInfo:nil];
	
	localUploadCount = filesLeft;
	
	[self refreshUploadCount];
}

- (void) uploadsDone {
	[globalNotificationCenter postNotificationName:@"DAHelperUploadsDone" object:nil userInfo:nil];
    
    if (localUploadCount > 0) {
        NSSound *systemSound = [NSSound soundNamed:@"Glass"];
        [systemSound play];
    }
	
	localUploadCount = 0;
	
	[self refreshUploadCount];
	
	statusView.uploading = NO;
	[statusView setNeedsDisplay:YES];
}

- (void) loggedin {
    [uploadStatus setTitle:@"All files up to date"];
    [statusView setToolTip:@"All files up to date"];
    statusView.offline = NO;
    [statusView setNeedsDisplay:YES];
	[logoutButton setEnabled:YES];
}

- (void) loggedout {
    [uploadStatus setTitle:@"Logged out"];
    [statusView setToolTip:@"Logged out"];
    statusView.offline = YES;
    [statusView setNeedsDisplay:YES];
	[logoutButton setEnabled:NO];
}

// Notifications coming from the main app

- (void) queueFileName:(NSNotification*) msg {
	NSString *fileName = [msg object];
	[dAStashUploader queueFileName:fileName folder:@"Desktop Uploads"];
}

- (void) refreshUploadInfo:(NSNotification*) msg {
	if (localUploadCount > 0) {
		[globalNotificationCenter postNotificationName:@"DAHelperUploadStarted" object:lastFileName userInfo:nil];
		[globalNotificationCenter postNotificationName:@"DAHelperUploadsRemaining" object:[NSString stringWithFormat:@"%d", localUploadCount] userInfo:nil];
		[globalNotificationCenter postNotificationName:@"DAHelperUploadProgress" object:[NSString stringWithFormat:@"%f", lastProgress] userInfo:nil];
	}
	
	if ([dAStashUploader isLoggedIn]) {
		[self loggedin];
	} else {
		[self loggedout];
	}
}

- (void) shutdown:(NSNotification*) msg {
	dontShutdownMainApp = YES;
	
	[NSApp terminate:self];
}

- (void) mainAppLaunched:(NSNotification*) msg {

}

// Actions

- (IBAction) openStash:(id)sender {
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://sta.sh"]];
}

- (IBAction) openHelp:(id)sender {
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://help.deviantart.com/deviantart/stash/"]];	
}

- (IBAction) openPreferences:(id)sender {
	[NSApp activateIgnoringOtherApps:YES];
	[preferences makeKeyAndOrderFront:self];
	[preferences center];
}

- (IBAction) openUpdates:(id)sender {
	[updater checkForUpdates:sender];
}

// Preferences

- (IBAction) requestLogout:(id)sender {
	[dAStashUploader logout];
}

- (IBAction) toggleStatusMenuColored:(id)sender {
	BOOL toggled = ([sender state] == NSOnState);
	
	statusView.colored = toggled;	
	[statusView setNeedsDisplay:YES];
	
	[defaults setBool:toggled forKey:@"isStatusIconColored"];
}

- (IBAction) toggleScreenshots:(id)sender {
	BOOL toggled = ([sender state] != NSOnState);
	
	[defaults setBool:toggled forKey:@"areScreenshotsNotUploaded"];
    [deleteScreenshotsSwitch setEnabled:!toggled];
}

- (IBAction) toggleDeleteScreenshots:(id)sender {
	BOOL toggled = ([sender state] == NSOnState);
	
	[defaults setBool:toggled forKey:@"areScreenshotsDeletedAfterUpload"];
}

- (IBAction) toggleIconOption:(id)sender {
	if ([statusIconOnly state] == 1 || [bothIcons state] == 1) {
		[statusView setHidden:NO];
		[defaults setBool:NO forKey:@"isStatusIconHidden"];
	} else {
		[statusView setHidden:YES];
		[defaults setBool:YES forKey:@"isStatusIconHidden"];
	}
	
	if ([dockIconOnly state] == 1 || [bothIcons state] == 1) {
		JAProcessInfo *procInfo = [[JAProcessInfo alloc] init];
		[procInfo obtainFreshProcessList];
		
		if ([procInfo findProcessesWithName:@"deviantART Sta.s"] < 1) {
			NSString *dockHelperPath = [NSString stringWithFormat:@"%@/Contents/Resources/DeviantART Sta.sh Uploader.app", [[NSBundle mainBundle] bundlePath]];
			[[NSWorkspace sharedWorkspace] launchApplication:dockHelperPath showIcon: YES autolaunch: NO];
		}
		[defaults setBool:YES forKey:@"isDockIconVisible"];
	} else {
		[globalNotificationCenter postNotificationName:@"DAHelperStopped" object:nil userInfo:nil];
		[defaults setBool:NO forKey:@"isDockIconVisible"];
	}
	[NSTimer scheduledTimerWithTimeInterval:0 target:self selector:@selector(openPreferences:) userInfo:nil repeats: NO];
}

- (BOOL) isLeopard {
    SInt32 major, minor, bugfix;
    Gestalt(gestaltSystemVersionMajor, &major);
    Gestalt(gestaltSystemVersionMinor, &minor);
    Gestalt(gestaltSystemVersionBugFix, &bugfix);
    
    return (major == 10 && minor == 6);
}

// Screenshots

- (void) metadataQueryUpdated:(NSNotification *)note {
    NSInteger previousLastSize = lastMetadataQuerySize;
    lastMetadataQuerySize = [metadataQuery resultCount];
    
    if ([defaults boolForKey:@"areScreenshotsNotUploaded"]) {
        return;
    }
    
    if ([metadataQuery resultCount] > 0) {
        for (long i = previousLastSize - 1; i <= [metadataQuery resultCount] - 1; i++) {
            NSMetadataItem *mditem = [metadataQuery resultAtIndex:i];
            NSString *filePath = [mditem valueForAttribute:(NSString *)kMDItemPath];
            NSError * err;
            NSDictionary * fileDict = [fileManager attributesOfItemAtPath:filePath error:&err];
            NSDate * fileDate = [fileDict objectForKey:@"NSFileModificationDate"];
            
            if ([fileDate timeIntervalSinceNow] > -10.0 && [screenshotsToUpload valueForKey:filePath] == nil) { // If file was last modified less than 10 seconds ago and hasn't been queued yet
                [screenshotsToUpload setValue:filePath forKey: filePath];
                [dAStashUploader queueFileName:filePath folder: @"Screenshot Uploads"];
            }
        }
    }
}

// Reachability

- (void) reachabilityChanged:(NSNotification* )note {
	Reachability* curReach = [note object];
	NSParameterAssert([curReach isKindOfClass: [Reachability class]]);
    
    if ([curReach currentReachabilityStatus] == NotReachable) {
        NSLog(@"Offline");
        [uploadStatus setTitle:@"Offline"];
        [statusView setToolTip:@"Offline"];
        statusView.offline = YES;
        [statusView setNeedsDisplay:YES];
    } else {
        NSLog(@"Online");
        if ([dAStashUploader isLoggedIn]) {
            [uploadStatus setTitle:@"All files up to date"];
            [statusView setToolTip:@"All files up to date"];
            statusView.offline = NO;
        } else {
            [uploadStatus setTitle:@"Logged out"];
            [statusView setToolTip:@"Logged out"];
            statusView.offline = YES;            
        }
        [statusView setNeedsDisplay:YES];
    }
}

@end
