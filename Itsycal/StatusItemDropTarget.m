//
//  StatusItemDropTarget.m
//  Itsycal
//

#import "StatusItemDropTarget.h"
#import "EventExtractor.h"

@implementation StatusItemDropTarget
{
    __weak NSStatusItem *_statusItem;
    BOOL (^_dropHandler)(NSPasteboard *);
}

- (instancetype)initWithStatusItem:(NSStatusItem *)statusItem dropHandler:(BOOL (^)(NSPasteboard *))dropHandler
{
    self = [super init];
    if (self) {
        _statusItem = statusItem;
        _dropHandler = [dropHandler copy];
        NSWindow *window = statusItem.button.window;
        [window registerForDraggedTypes:[EventExtractor readablePasteboardTypes]];
        window.delegate = self;
    }
    return self;
}

- (void)setHovering:(BOOL)hovering
{
    // The status item doesn't highlight (see -createStatusItem),
    // so dim it to show it will accept the drop.
    _statusItem.button.alphaValue = hovering ? 0.5 : 1;
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender
{
    if (![EventExtractor canReadPasteboard:sender.draggingPasteboard]) {
        return NSDragOperationNone;
    }
    [self setHovering:YES];
    return NSDragOperationCopy;
}

- (void)draggingExited:(id<NSDraggingInfo>)sender
{
    [self setHovering:NO];
}

- (void)draggingEnded:(id<NSDraggingInfo>)sender
{
    [self setHovering:NO];
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender
{
    [self setHovering:NO];
    return _dropHandler(sender.draggingPasteboard);
}

@end
