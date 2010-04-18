#import <Foundation/Foundation.h>
#import <sysexits.h>

static void usage( void ) __dead2;

static void usage( void )
{
    fprintf( stderr, "Usage: iphone-legacy-fix [path]\n" );
    fprintf( stderr, "  Arguments:\n" );
    fprintf( stderr, "    path: The path to the Developer Tools folder you want to modify.\n" );
    fprintf( stderr, "NOTE: This application must run as root to have permission to modify the SDK folders.\n" );
    fflush( stderr );
    exit( EX_USAGE );
}

int main (int argc, const char * argv[])
{
    if ( geteuid() != 0 )
        usage();
    if ( argc != 2 )
        usage();    // dead call, terminates app
    
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
    
    NSString * devtoolsPath = [[NSString stringWithUTF8String: argv[1]] stringByStandardizingPath];
    NSString * sdksPath = [devtoolsPath stringByAppendingPathComponent: [NSString pathWithComponents: [NSArray arrayWithObjects: @"Platforms", @"iPhoneSimulator.platform", @"Developer", @"SDKs", nil]]];
    
    // we set up a serial queue to run filesystem operations in such a way that the disk won't thrash
    dispatch_queue_t fsOpQueue = dispatch_queue_create( "net.alanquatermain.fsOperationQueue", NULL );
    // our queue will target the main queue, so operations get run when we call dispatch_main() later
    dispatch_set_target_queue( fsOpQueue, dispatch_get_main_queue() );
    
    NSError * error = nil;
    NSArray * contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath: sdksPath error: &error];
    if ( [contents count] == 0 )
    {
        NSLog( @"No simulator SDKs found at path '%@'", sdksPath );
        return ( 0 );
    }
    
    NSArray * oldSDKPaths = [contents filteredArrayUsingPredicate: [NSPredicate predicateWithBlock: ^(id obj, NSDictionary *bindings) {
        if ( [obj hasSuffix: @"3.0.sdk"] )
            return ( NO );
        return ( YES );
    }]];
    
    [oldSDKPaths enumerateObjectsUsingBlock: ^(id obj, NSUInteger idx, BOOL * stop) {
        NSString * gcc = [sdksPath stringByAppendingPathComponent: [NSString pathWithComponents: [NSArray arrayWithObjects: obj, @"usr", @"lib", @"gcc", nil]]];
        NSString * darwin9 = [gcc stringByAppendingPathComponent: @"i686-apple-darwin9"];
        NSString * darwin10 = [gcc stringByAppendingPathComponent: @"i686-apple-darwin10"];
        
        // skip anything with a pre-existing darwin10 folder
        if ( [[NSFileManager defaultManager] fileExistsAtPath: darwin10] )
            return;
        
        // if there's not darwin9 folder, we can't do anything
        if ( [[NSFileManager defaultManager] fileExistsAtPath: darwin9] == NO )
            return;
        
        // create a symlink from darwin10 to darwin9
        dispatch_async( fsOpQueue, ^{
            NSError * myError = nil;
            if ( [[NSFileManager defaultManager] createSymbolicLinkAtPath: darwin10 withDestinationPath: darwin9 error: &myError] == NO )
            {
                NSLog( @"Error linking %@ to %@: %@", darwin10, darwin9, myError );
            }
        });
    }];
    
    // we put this at the end of the queue so we'll quit nicely
    dispatch_async( fsOpQueue, ^{
        CFRunLoopStop( CFRunLoopGetMain() );
    });
    
    CFRunLoopRun();
    
    [pool drain];
    
    return ( 0 );
}
