#include "nativechrome.h"

#include <QColor>
#include <QCoreApplication>
#include <QTranslator>
#include <QGuiApplication>
#include <QQmlEngine>
#include <QQuickImageProvider>
#include <QQuickWindow>

#import <AppKit/AppKit.h>
#import <objc/runtime.h>

// Built without ARC, so ownership below is manual.

static NSToolbarItemIdentifier const kBackItem = @"com.moonlight-stream.back";
static NSToolbarItemIdentifier const kTitleItem = @"com.moonlight-stream.title";
static NSToolbarItemIdentifier const kUpdateItem = @"com.moonlight-stream.update";
static NSToolbarItemIdentifier const kAddPcItem = @"com.moonlight-stream.addpc";
static NSToolbarItemIdentifier const kHelpItem = @"com.moonlight-stream.help";
static NSToolbarItemIdentifier const kSettingsItem = @"com.moonlight-stream.settings";

// The main window's saved size and position (NSWindow frame autosave)
static NSString* const kWindowFrameName = @"MoonlightMainWindow";

// The interface font (Orbix without its digits) as data, from setInterfaceFontData()
static NSData* s_InterfaceFontData = nil;

// The window title's font: the interface font at the size of AppKit's toolbar title (15 pt),
// falling back to the system font for the digits and anything else Orbix lacks. Without the
// interface font, AppKit's own title font.
static NSFont* titleFont()
{
    static NSFont* font = nil;
    if (font == nil) {
        const CGFloat size = 15;
        CTFontDescriptorRef orbix = s_InterfaceFontData != nil ?
                                        CTFontManagerCreateFontDescriptorFromData((CFDataRef)s_InterfaceFontData) : NULL;
        if (orbix != NULL) {
            NSDictionary* cascade = @{ (NSString*)kCTFontCascadeListAttribute :
                                           @[ [NSFont systemFontOfSize:size].fontDescriptor ] };
            CTFontDescriptorRef withFallback = CTFontDescriptorCreateCopyWithAttributes(orbix, (CFDictionaryRef)cascade);
            font = (NSFont*)CTFontCreateWithFontDescriptor(withFallback, size, NULL);
            CFRelease(withFallback);
            CFRelease(orbix);
        }
        if (font == nil) {
            font = [[NSFont systemFontOfSize:size weight:NSFontWeightSemibold] retain];
        }
    }
    return font;
}

// The window title, drawn by Moonlight in the interface font in place of AppKit's (the
// window's own title stays set but hidden, for the Window menu, Mission Control and
// VoiceOver). Like AppKit's title it dims while the window isn't the active one. Clicks go
// through to the title bar, so dragging the window and double-click to zoom work on it.
@interface MLTitleField : NSTextField
@end

@implementation MLTitleField

- (instancetype)init
{
    if ((self = [super initWithFrame:NSZeroRect])) {
        self.editable = NO;
        self.selectable = NO;
        self.bordered = NO;
        self.drawsBackground = NO;
        self.font = titleFont();
        self.lineBreakMode = NSLineBreakByTruncatingTail;
        self.cell.usesSingleLineMode = YES;
        self.accessibilityElement = NO;  // The window's title already says it
        self.translatesAutoresizingMaskIntoConstraints = NO;
        // Shrinks (truncating) before anything else in the title bar does
        [self setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow - 1
                                       forOrientation:NSLayoutConstraintOrientationHorizontal];
        [self setContentHuggingPriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];
        [self updateActiveState];
    }
    return self;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [super dealloc];
}

- (NSView*)hitTest:(NSPoint)point
{
    return nil;
}

- (BOOL)mouseDownCanMoveWindow
{
    return YES;
}

- (void)viewWillMoveToWindow:(NSWindow*)newWindow
{
    NSNotificationCenter* center = NSNotificationCenter.defaultCenter;
    [center removeObserver:self];
    if (newWindow != nil) {
        for (NSNotificationName name in @[ NSWindowDidBecomeMainNotification, NSWindowDidResignMainNotification,
                                           NSWindowDidBecomeKeyNotification, NSWindowDidResignKeyNotification ]) {
            [center addObserver:self selector:@selector(activeStateChanged:) name:name object:newWindow];
        }
        for (NSNotificationName name in @[ NSApplicationDidBecomeActiveNotification, NSApplicationDidResignActiveNotification ]) {
            [center addObserver:self selector:@selector(activeStateChanged:) name:name object:nil];
        }
    }
    [super viewWillMoveToWindow:newWindow];
}

- (void)viewDidMoveToWindow
{
    [super viewDidMoveToWindow];
    [self updateActiveState];
}

- (void)activeStateChanged:(NSNotification*)notification
{
    [self updateActiveState];
}

- (void)updateActiveState
{
    NSWindow* window = self.window;
    BOOL active = window == nil || (NSApp.isActive && (window.isMainWindow || window.isKeyWindow));
    self.textColor = active ? NSColor.labelColor : NSColor.tertiaryLabelColor;
}

@end

@interface MLToolbarController : NSObject <NSToolbarDelegate>
{
@public
    NativeChrome* chrome;
    NSToolbar* toolbar;
    NSMutableDictionary<NSToolbarItemIdentifier, NSToolbarItem*>* items;
    MLTitleField* titleField;
}
- (void)refresh;
- (void)setTitle:(NSString*)title;
@end

@implementation MLToolbarController

- (instancetype)initWithChrome:(NativeChrome*)owner
{
    if ((self = [super init])) {
        chrome = owner;
        items = [[NSMutableDictionary alloc] init];

        [self addItem:kBackItem symbol:@"chevron.backward" label:@"Back" action:@selector(back:)];
        [self addItem:kUpdateItem symbol:@"arrow.down.circle" label:@"Update" action:@selector(update:)];
        [self addItem:kAddPcItem symbol:@"plus" label:@"Add Computer" action:@selector(addPc:)];
        [self addItem:kHelpItem symbol:@"questionmark.circle" label:@"Help" action:@selector(help:)];
        [self addItem:kSettingsItem symbol:@"gearshape" label:@"Settings" action:@selector(settings:)];

        // The back button leads, like Finder and Safari; everything else trails
        items[kBackItem].navigational = YES;

        // The title where AppKit puts its own, after the back button
        titleField = [[MLTitleField alloc] init];
        NSToolbarItem* titleItem = [[NSToolbarItem alloc] initWithItemIdentifier:kTitleItem];
        titleItem.view = titleField;
        titleItem.bordered = NO;  // No glass capsule behind it on macOS 26
        titleItem.label = @"";
        items[kTitleItem] = titleItem;
        [titleItem release];

        toolbar = [[NSToolbar alloc] initWithIdentifier:@"com.moonlight-stream.main"];
        toolbar.delegate = self;
        toolbar.displayMode = NSToolbarDisplayModeIconOnly;
        toolbar.allowsUserCustomization = NO;
    }
    return self;
}

- (void)dealloc
{
    toolbar.delegate = nil;
    [toolbar release];
    [items release];
    [titleField release];
    [super dealloc];
}

- (void)addItem:(NSToolbarItemIdentifier)identifier symbol:(NSString*)symbol label:(NSString*)label action:(SEL)action
{
    NSToolbarItem* item = [[NSToolbarItem alloc] initWithItemIdentifier:identifier];
    item.image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:label];
    item.label = label;
    item.paletteLabel = label;
    item.toolTip = label;
    item.target = self;
    item.action = action;
    item.bordered = YES;
    items[identifier] = item;
    [item release];
}

- (NSArray<NSToolbarItemIdentifier>*)toolbarDefaultItemIdentifiers:(NSToolbar*)bar
{
    return @[ kBackItem, kTitleItem, NSToolbarFlexibleSpaceItemIdentifier, kUpdateItem, kAddPcItem, kHelpItem, kSettingsItem ];
}

- (NSArray<NSToolbarItemIdentifier>*)toolbarAllowedItemIdentifiers:(NSToolbar*)bar
{
    return [self toolbarDefaultItemIdentifiers:bar];
}

- (NSToolbarItem*)toolbar:(NSToolbar*)bar itemForItemIdentifier:(NSToolbarItemIdentifier)identifier willBeInsertedIntoToolbar:(BOOL)flag
{
    return items[identifier];
}

- (void)setItem:(NSToolbarItemIdentifier)identifier visible:(BOOL)visible
{
    NSToolbarItem* item = items[identifier];
    // NSToolbarItem.hidden is macOS 15+; on older systems disable the item instead
    if (@available(macOS 15.0, *)) {
        item.hidden = !visible;
    }
    item.enabled = visible;
}

- (void)refresh
{
    [self setItem:kBackItem visible:chrome->canGoBack()];
    [self setItem:kAddPcItem visible:chrome->showAddPc()];
    [self setItem:kHelpItem visible:chrome->showHelp()];
    [self setItem:kSettingsItem visible:chrome->showSettings()];
    items[kSettingsItem].image = [NSImage imageWithSystemSymbolName:chrome->settingsOpen() ? @"gearshape.fill" : @"gearshape"
                                            accessibilityDescription:@"Settings"];

    QString updateText = chrome->updateText();
    [self setItem:kUpdateItem visible:!updateText.isEmpty()];
    items[kUpdateItem].toolTip = updateText.toNSString();
}

- (void)setTitle:(NSString*)title
{
    titleField.stringValue = title;
}

- (void)back:(id)sender { emit chrome->backClicked(); }
- (void)update:(id)sender { emit chrome->updateClicked(); }
- (void)addPc:(id)sender { emit chrome->addPcClicked(); }
- (void)help:(id)sender { emit chrome->helpClicked(); }
- (void)settings:(id)sender { emit chrome->settingsClicked(); }

@end

// Renders "image://sfsymbol/<name>/<RRGGBB>" as the SF Symbol in that color, or
// "image://sfsymbol/<name>/multicolor" in the symbol's own colors (like the yellow alert triangle)
class SfSymbolImageProvider : public QQuickImageProvider
{
public:
    SfSymbolImageProvider() : QQuickImageProvider(QQuickImageProvider::Image) {}

    QImage requestImage(const QString& id, QSize* size, const QSize& requestedSize) override
    {
        @autoreleasepool {
            int slash = id.lastIndexOf('/');
            QString name = slash > 0 ? id.left(slash) : id;
            QString colorSpec = slash > 0 ? id.mid(slash + 1) : QString();
            bool multicolor = colorSpec == QLatin1String("multicolor");
            QColor color = !colorSpec.isEmpty() && !multicolor ? QColor("#" + colorSpec) : QColor(Qt::white);

            // Render at 2x so it stays sharp on Retina displays
            int logical = qMax(16, requestedSize.isValid() ? qMax(requestedSize.width(), requestedSize.height()) : 64);
            int pixels = logical * 2;

            NSImage* symbol = [NSImage imageWithSystemSymbolName:name.toNSString() accessibilityDescription:nil];
            if (symbol == nil) {
                if (size) {
                    *size = QSize();
                }
                return QImage();
            }

            NSColor* tint = [NSColor colorWithSRGBRed:color.redF() green:color.greenF() blue:color.blueF() alpha:color.alphaF()];
            NSImageSymbolConfiguration* coloring = multicolor ? [NSImageSymbolConfiguration configurationPreferringMulticolor]
                                                              : [NSImageSymbolConfiguration configurationWithHierarchicalColor:tint];
            NSImageSymbolConfiguration* config =
                [[NSImageSymbolConfiguration configurationWithPointSize:pixels * 0.8 weight:NSFontWeightRegular]
                    configurationByApplyingConfiguration:coloring];
            symbol = [symbol imageWithSymbolConfiguration:config];

            // Fit the symbol into a square canvas, keeping its aspect ratio
            NSSize symbolSize = symbol.size;
            CGFloat scale = pixels / qMax(symbolSize.width, symbolSize.height);
            NSRect target = NSMakeRect((pixels - symbolSize.width * scale) / 2, (pixels - symbolSize.height * scale) / 2,
                                       symbolSize.width * scale, symbolSize.height * scale);

            QImage image(pixels, pixels, QImage::Format_ARGB32_Premultiplied);
            image.fill(Qt::transparent);

            CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
            CGContextRef context = CGBitmapContextCreate(image.bits(), pixels, pixels, 8, image.bytesPerLine(), colorSpace,
                                                         kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host);
            CGColorSpaceRelease(colorSpace);

            NSGraphicsContext* nsContext = [NSGraphicsContext graphicsContextWithCGContext:context flipped:NO];
            [NSGraphicsContext saveGraphicsState];
            [NSGraphicsContext setCurrentContext:nsContext];
            [symbol drawInRect:target fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0];
            [NSGraphicsContext restoreGraphicsState];
            CGContextRelease(context);

            if (size) {
                *size = image.size();
            }
            return image;
        }
    }
};

NativeChrome::NativeChrome(QObject* parent)
    : QObject(parent)
{
}

NativeChrome::~NativeChrome()
{
    [(MLToolbarController*)m_Native release];
}

// Qt's application menu still says "Preferences..."; macOS 13 and later say "Settings…".
// Qt re-reads the label through this translation whenever it syncs the menu, so answering
// it here keeps the new label (a language translator installed later still takes over).
class AppMenuTranslator : public QTranslator
{
public:
    using QTranslator::QTranslator;

    QString translate(const char* context, const char* sourceText, const char* disambiguation, int n) const override
    {
        Q_UNUSED(disambiguation)
        Q_UNUSED(n)
        if (qstrcmp(context, "MAC_APPLICATION_MENU") == 0 && qstrcmp(sourceText, "Preferences...") == 0) {
            return QStringLiteral("Settings…");
        }
        return QString();
    }

    bool isEmpty() const override
    {
        return false;
    }
};

void NativeChrome::registerTypes(QQmlEngine* engine)
{
    QCoreApplication::installTranslator(new AppMenuTranslator(QCoreApplication::instance()));

    engine->addImageProvider("sfsymbol", new SfSymbolImageProvider());
    qmlRegisterSingletonType<NativeChrome>("NativeChrome", 1, 0, "NativeChrome",
                                           [](QQmlEngine*, QJSEngine*) -> QObject* {
                                               return new NativeChrome();
                                           });
}

bool NativeChrome::isEnabled() const
{
    return true;
}

void NativeChrome::attach(QQuickWindow* window)
{
    // Only a Cocoa window has an NSView behind it (not, say, the offscreen platform)
    if (window == nullptr || m_Native != nullptr || QGuiApplication::platformName() != QLatin1String("cocoa")) {
        return;
    }

    NSView* qtView = reinterpret_cast<NSView*>(window->winId());
    NSWindow* nsWindow = qtView.window;
    if (nsWindow == nil) {
        return;
    }

    // Window resizes (Settings growing and shrinking the window) animate at AppKit's
    // default 0.2 s per 150 points, which is about half a second for Settings. Give
    // Moonlight's window class a fixed, quicker duration instead.
    static dispatch_once_t quickResize;
    dispatch_once(&quickResize, ^{
        IMP quick = imp_implementationWithBlock(^NSTimeInterval(id, NSRect) {
            return 0.18;
        });
        class_replaceMethod([nsWindow class], @selector(animationResizeTime:), quick, "d@:{CGRect={CGPoint=dd}{CGSize=dd}}");
    });

    // Reopen where the window was last time (setting the name restores the saved frame),
    // unless the user asked for a maximized or full-screen window
    if (window->visibility() == QWindow::Windowed) {
        [nsWindow setFrameAutosaveName:kWindowFrameName];
    }

    // Toolbar in the title bar, with the title and traffic lights, as in Finder and Safari.
    // On macOS 26 and later the system draws its items on Liquid Glass.
    MLToolbarController* controller = [[MLToolbarController alloc] initWithChrome:this];
    m_Native = controller;
    nsWindow.toolbar = controller->toolbar;
    nsWindow.toolbarStyle = NSWindowToolbarStyleUnified;
    nsWindow.titlebarAppearsTransparent = YES;
    updateToolbar();

    // The title in the interface font, in a toolbar item in place of AppKit's
    nsWindow.titleVisibility = NSWindowTitleHidden;
    [controller setTitle:window->title().toNSString()];
    QObject::connect(window, &QWindow::windowTitleChanged, this, [this](const QString& title) {
        [(MLToolbarController*)m_Native setTitle:title.toNSString()];
    });

    // Translucent glass behind Moonlight's content. The Qt view draws on top with
    // a transparent background. NSGlassEffectView is macOS 26+; older systems get
    // the window-background vibrancy material.
    nsWindow.opaque = NO;
    nsWindow.backgroundColor = NSColor.clearColor;

    NSView* frameView = qtView.superview;
    NSView* backdrop = nil;
    Class glassClass = NSClassFromString(@"NSGlassEffectView");
    if (glassClass != nil) {
        backdrop = [[glassClass alloc] initWithFrame:frameView.bounds];
        if ([backdrop respondsToSelector:@selector(setCornerRadius:)]) {
            [(id)backdrop setCornerRadius:0];
        }
        // A light wash of the window color keeps text readable over busy desktops
        if ([backdrop respondsToSelector:@selector(setTintColor:)]) {
            [(id)backdrop setTintColor:[NSColor.windowBackgroundColor colorWithAlphaComponent:0.45]];
        }
    }
    else {
        NSVisualEffectView* effect = [[NSVisualEffectView alloc] initWithFrame:frameView.bounds];
        effect.material = NSVisualEffectMaterialUnderWindowBackground;
        effect.blendingMode = NSVisualEffectBlendingModeBehindWindow;
        effect.state = NSVisualEffectStateFollowsWindowActiveState;
        backdrop = effect;
    }
    backdrop.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [frameView addSubview:backdrop positioned:NSWindowBelow relativeTo:qtView];
    [backdrop release];
}

void NativeChrome::setWindowGeometry(QQuickWindow* window, qreal x, qreal y, qreal width, qreal height, bool animate)
{
    if (window == nullptr) {
        return;
    }

    NSWindow* nsWindow = QGuiApplication::platformName() == QLatin1String("cocoa") ?
                             reinterpret_cast<NSView*>(window->winId()).window : nil;
    // AppKit only runs the animation on a live display: on a hidden window (screen locked,
    // display asleep) the call would block waiting for it, so just move it there
    if (nsWindow == nil || !animate || !(nsWindow.occlusionState & NSWindowOcclusionStateVisible)) {
        window->setGeometry(qRound(x), qRound(y), qRound(width), qRound(height));
        return;
    }

    // Apply the change in the content area to the whole frame (title bar and toolbar
    // included), converting Qt's top-left origin to Cocoa's bottom-left one
    QRect current = window->geometry();
    NSRect frame = nsWindow.frame;
    CGFloat top = NSMaxY(frame) - (y - current.y());
    frame.origin.x += x - current.x();
    frame.size.width += width - current.width();
    frame.size.height += height - current.height();
    frame.origin.y = top - frame.size.height;

    [nsWindow setFrame:frame display:YES animate:YES];
}

static NSWindow* nativeWindow(QQuickWindow* window)
{
    if (window == nullptr || QGuiApplication::platformName() != QLatin1String("cocoa")) {
        return nil;
    }
    return reinterpret_cast<NSView*>(window->winId()).window;
}

void NativeChrome::setRememberWindowFrame(QQuickWindow* window, bool remember)
{
    NSWindow* nsWindow = nativeWindow(window);
    if (nsWindow == nil) {
        return;
    }

    if (remember) {
        // Keep the window where it is now (setting the name alone would jump back to
        // the frame saved before it was turned off)
        [nsWindow saveFrameUsingName:kWindowFrameName];
        [nsWindow setFrameAutosaveName:kWindowFrameName];
    }
    else {
        [nsWindow setFrameAutosaveName:@""];
    }
}

void NativeChrome::showAboutPanel()
{
    [NSApp orderFrontStandardAboutPanel:nil];
    if (@available(macOS 14.0, *)) {
        [NSApp activate];
    }
    else {
        [NSApp activateIgnoringOtherApps:YES];
    }
}

QStringList NativeChrome::appMenuItems() const
{
    QStringList items;
    if (NSApp.mainMenu.numberOfItems == 0) {
        return items;
    }
    NSMenu* appMenu = [NSApp.mainMenu itemAtIndex:0].submenu;
    [appMenu update];
    for (NSMenuItem* item in appMenu.itemArray) {
        if (item.isSeparatorItem || item.isHidden) {
            continue;
        }
        BOOL enabled = item.target != nil && [item.target respondsToSelector:@selector(validateMenuItem:)]
                           ? [item.target validateMenuItem:item] : item.isEnabled;
        items.append(QString::fromNSString(item.title) + (enabled ? "|enabled" : "|disabled"));
    }
    return items;
}

QString NativeChrome::symbol(const QString& name, const QColor& color) const
{
    return QStringLiteral("image://sfsymbol/%1/%2").arg(name, color.name(QColor::HexRgb).mid(1));
}

void NativeChrome::updateToolbar()
{
    [(MLToolbarController*)m_Native refresh];
}

void NativeChrome::setInterfaceFontData(const QByteArray& data)
{
    [s_InterfaceFontData release];
    s_InterfaceFontData = data.isEmpty() ? nil : [data.toNSData() retain];
}

void NativeChrome::useInterfaceFontForTitle(void* nativeWindow)
{
    NSWindow* nsWindow = (NSWindow*)nativeWindow;
    NSButton* zoom = [nsWindow standardWindowButton:NSWindowZoomButton];
    NSView* titlebar = zoom.superview;
    if (nsWindow == nil || titlebar == nil || nsWindow.toolbar != nil || nsWindow.title.length == 0) {
        return;
    }

    // Centred in the title bar like AppKit's title, clear of the traffic lights
    MLTitleField* field = [[MLTitleField alloc] init];
    field.stringValue = nsWindow.title;
    field.alignment = NSTextAlignmentCenter;
    [titlebar addSubview:field];
    NSLayoutConstraint* centred = [field.centerXAnchor constraintEqualToAnchor:titlebar.centerXAnchor];
    centred.priority = NSLayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        centred,
        [field.centerYAnchor constraintEqualToAnchor:zoom.centerYAnchor],
        [field.leadingAnchor constraintGreaterThanOrEqualToAnchor:zoom.trailingAnchor constant:12],
        [field.trailingAnchor constraintLessThanOrEqualToAnchor:titlebar.trailingAnchor constant:-12],
    ]];
    [field release];
    nsWindow.titleVisibility = NSWindowTitleHidden;
}

void NativeChrome::useInterfaceFontForTitle(QWindow* window)
{
    if (window != nullptr && QGuiApplication::platformName() == QLatin1String("cocoa")) {
        useInterfaceFontForTitle(reinterpret_cast<NSView*>(window->winId()).window);
    }
}

// The app menu's Quit item (Qt's: the terminate: action, or else the one on Cmd+Q)
static NSMenuItem* quitMenuItem()
{
    if (NSApp.mainMenu.numberOfItems == 0) {
        return nil;
    }
    NSMenu* appMenu = [NSApp.mainMenu itemAtIndex:0].submenu;
    for (NSMenuItem* item in appMenu.itemArray) {
        if (item.action == @selector(terminate:)) {
            return item;
        }
    }
    for (NSMenuItem* item in appMenu.itemArray) {
        if ([item.keyEquivalent isEqualToString:@"q"] &&
            (item.keyEquivalentModifierMask & NSEventModifierFlagDeviceIndependentFlagsMask) == NSEventModifierFlagCommand) {
            return item;
        }
    }
    return nil;
}

void NativeChrome::setQuitEndsSession(bool endsSession)
{
    static NSString* quitTitle = nil;
    NSMenuItem* item = quitMenuItem();
    if (item == nil) {
        return;
    }
    if (endsSession) {
        if (quitTitle == nil) {
            quitTitle = [item.title copy];
        }
        item.title = QCoreApplication::translate("NativeChrome", "Disconnect").toNSString();
    }
    else if (quitTitle != nil) {
        item.title = quitTitle;
        [quitTitle release];
        quitTitle = nil;
    }
}

bool NativeChrome::isQuitFromOutside()
{
    // Dock > Quit, logout, restart and shutdown arrive as a Quit Apple Event; Cmd+Q and
    // the menu call -[NSApplication terminate:] directly
    NSAppleEventDescriptor* event = NSAppleEventManager.sharedAppleEventManager.currentAppleEvent;
    return event != nil && event.eventClass == kCoreEventClass && event.eventID == kAEQuitApplication;
}

void NativeChrome::triggerQuitMenuItem()
{
    NSMenuItem* item = quitMenuItem();
    if (item != nil) {
        [item.menu performActionForItemAtIndex:[item.menu indexOfItem:item]];
    }
}

void NativeChrome::sendQuitAppleEvent()
{
    NSAppleEventDescriptor* quit =
        [NSAppleEventDescriptor appleEventWithEventClass:kCoreEventClass
                                                 eventID:kAEQuitApplication
                                        targetDescriptor:[NSAppleEventDescriptor currentProcessDescriptor]
                                                returnID:kAutoGenerateReturnID
                                           transactionID:kAnyTransactionID];
    [quit sendEventWithOptions:NSAppleEventSendNoReply timeout:5 error:nil];
}
