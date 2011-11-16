// Copyright © 1999-2011 deviantART Inc.

#import <Cocoa/Cocoa.h>
#import <CommonCrypto/CommonDigest.h>
#import <DeviantART/DA.h>
#import <Sparkle/Sparkle.h>
#import "StatusView.h"

@interface AppDelegate : NSObject<DAStashUploaderDelegate, NSMetadataQueryDelegate> {
	SUUpdater *updater;
	DAStashUploader *dAStashUploader;
	NSMutableDictionary *uploadFileNames;
	NSMutableArray *recentlyUploadedList;
	NSMutableArray *folderQueue;
	
	NSString *lastFileName;
	NSStatusItem *statusItem;
	NSUserDefaults *defaults;
	NSDistributedNotificationCenter *globalNotificationCenter;
	NSFileManager *fileManager;
	
	IBOutlet StatusView *statusView;
	IBOutlet NSMenu *statusMenu;
	IBOutlet NSMenuItem *uploadStatus;
	
	float lastProgress;
	int localUploadCount;
	BOOL dontShutdownMainApp;
	BOOL delayedOpenPreferences;
	NSInteger originalMenuCount;
    
    // Screenshots
    NSMetadataQuery *metadataQuery;
    NSInteger lastMetadataQuerySize;
    NSMutableDictionary *screenshotsToUpload;
	
	// Preferences
	IBOutlet NSWindow *preferences;
	
	IBOutlet NSButton *colorSwitch;
	IBOutlet NSButton *logoutButton;
	IBOutlet NSPopUpButton *iconMenu;
	IBOutlet NSMenuItem *statusIconOnly;
	IBOutlet NSMenuItem *dockIconOnly;
	IBOutlet NSMenuItem *bothIcons;
    IBOutlet NSButton *screenshotsSwitch;
    IBOutlet NSButton *deleteScreenshotsSwitch;
}

+ (void) addToLoginItems:(NSURL *)itemURL enabled:(BOOL)enabled;

- (void) applicationDidFinishLaunching:(NSNotification*)notice;
- (void) queueFileNames:(NSArray *)files fromDrag:(BOOL)fromDrag;
- (void) persistLists;

- (IBAction) openStash:(id)sender;
- (IBAction) openHelp:(id)sender;
- (IBAction) openPreferences:(id)sender;
- (IBAction) openUpdates:(id)sender;
- (void) addItemToStatusMenu:(NSString*)title withURL:(NSString*)url;

// DAStashUploaderDelegate protocol

- (void) uploadStarted:(NSString*)fileName;
- (void) uploadProgress:(float)newProgress;
- (void) uploadDone:(NSInteger)aStashid folderId: (NSInteger)aFolderId;
- (void) uploadError:(NSString*)errorHuman;
- (void) uploadsRemaining:(unsigned int)filesLeft total:(unsigned int)total;
- (void) uploadsDone;
- (void) loggedout;
- (void) loggedin;
- (void) internetOnline;
- (void) internetOffline;

// Preferences
- (IBAction) requestLogout:(id)sender;
- (IBAction) toggleStatusMenuColored:(id)sender;
- (IBAction) toggleScreenshots:(id)sender;
- (IBAction) toggleDeleteScreenshots:(id)sender;
- (IBAction) toggleIconOption:(id)sender;

- (BOOL) isLeopard;

// Screenshots
- (void) metadataQueryUpdated:(NSNotification *)note;

@end