//
//  MMScrappedPaperView.m
//  LooseLeaf
//
//  Created by Adam Wulf on 8/23/13.
//  Copyright (c) 2013 Milestone Made, LLC. All rights reserved.
//

#import "MMScrappedPaperView.h"
#import "PolygonToolDelegate.h"
#import "MMScrapView.h"
#import "MMScrapContainerView.h"
#import "NSThread+BlockAdditions.h"
#import "NSArray+Extras.h"
#import <JotUI/JotUI.h>
#import <JotUI/AbstractBezierPathElement-Protected.h>
#import "MMDebugDrawView.h"
#import "MMScrapsOnPaperState.h"
#import "MMImmutableScrapsOnPaperState.h"
#import <JotUI/UIColor+JotHelper.h>
#import <DrawKit-iOS/DrawKit-iOS.h>
#import "DKUIBezierPathClippedSegment+PathElement.h"
#import "UIBezierPath+PathElement.h"
#import "UIBezierPath+Description.h"


@implementation MMScrappedPaperView{
    UIView* scrapContainerView;
    NSString* scrapIDsPath;
    MMScrapsOnPaperState* scrapState;
}


static dispatch_queue_t concurrentBackgroundQueue;
+(dispatch_queue_t) concurrentBackgroundQueue{
    if(!concurrentBackgroundQueue){
        concurrentBackgroundQueue = dispatch_queue_create("com.milestonemade.looseleaf.scraps.concurrentBackgroundQueue", DISPATCH_QUEUE_CONCURRENT);
    }
    return concurrentBackgroundQueue;
}

- (id)initWithFrame:(CGRect)frame andUUID:(NSString*)_uuid{
    self = [super initWithFrame:frame andUUID:_uuid];
    if (self) {
        // Initialization code
        scrapContainerView = [[MMScrapContainerView alloc] initWithFrame:self.bounds];
        [self.contentView addSubview:scrapContainerView];
        // anchor the view to the top left,
        // so that when we scale down, the drawable view
        // stays in place
        scrapContainerView.layer.anchorPoint = CGPointMake(0,0);
        scrapContainerView.layer.position = CGPointMake(0,0);

        panGesture.scrapDelegate = self;
        
        scrapState = [[MMScrapsOnPaperState alloc] initWithScrapIDsPath:self.scrapIDsPath];
        scrapState.delegate = self;
    }
    return self;
}


#pragma mark - Scraps

/**
 * the input path contains the offset
 * and size of the new scrap from its
 * bounds
 */
-(MMScrapView*) addScrapWithPath:(UIBezierPath*)path{

    // find our current "best" of an unrotated path
    CGRect pathBounds = path.bounds;
    CGFloat initialSize = pathBounds.size.width * pathBounds.size.height;
    CGFloat lastBestSize = initialSize;
    CGFloat lastBestRotation = 0;
    
    // now copy the path, and we'll rotate this to
    // find the best rotation that'll give us the
    // minimum (or very close to min) square pixels
    // to use as the backing
    UIBezierPath* rotatedPath = [path copy];
    
    CGFloat numberOfSteps = 30.0;
    CGAffineTransform rotationTransform = CGAffineTransformMakeRotation(M_PI / 2.0 / numberOfSteps);
    CGFloat currentStepRotation = 0;
    for(int i=0;i<numberOfSteps;i++){
        // rotate the path, and track what that rotation value is:
        currentStepRotation += M_PI / 2.0 / numberOfSteps;
        [rotatedPath applyTransform:rotationTransform];
        // now calculate how many square pixels we'd need
        // to store that new path
        CGRect rotatedPathBounds = rotatedPath.bounds;
        CGFloat rotatedPxSize = rotatedPathBounds.size.width * rotatedPathBounds.size.height;
        // if it's fewer square pixels, then save
        // that rotation value
        if(rotatedPxSize < lastBestSize){
            lastBestRotation = currentStepRotation;
            lastBestSize = rotatedPxSize;
        }
    }
    
//    NSLog(@"memory savings of: %f", (1 - lastBestSize / initialSize));
    
    if(lastBestRotation){
        [path rotateAndAlignCenter:lastBestRotation];
    }

    // now add the scrap, and rotate it to counter-act
    // the rotation we added to the path itself
    return [self addScrapWithPath:path andRotation:-lastBestRotation];
}




/**
 * the input path contains the offset
 * and size of the new scrap from its
 * bounds
 */
-(MMScrapView*) addScrapWithPath:(UIBezierPath*)path andRotation:(CGFloat)lastBestRotation{
    //
    // at this point, we have the correct path and rotation that will
    // give us the minimal square px. For instance, drawing a thin diagonal
    // strip of paper will create a thin texture and rotate it, instead of
    // an unrotated thick rectangle.
    
    CGPoint pathCenter = path.center;
    
    MMScrapView* newScrap = [[MMScrapView alloc] initWithBezierPath:path];
    @synchronized(scrapContainerView){
        [scrapContainerView addSubview:newScrap];
    }
    [newScrap loadStateAsynchronously:NO];
    [newScrap setShouldShowShadow:[self isEditable]];
    
    [newScrap setScale:1.00];
    [newScrap setRotation:lastBestRotation];

    CGPoint scrapCenter = newScrap.center;
    
    NSLog(@"pc: %f %f", pathCenter.x, pathCenter.y);
    NSLog(@"xc: %f %f", scrapCenter.x, scrapCenter.y);
    
    //    [UIView animateWithDuration:0.4 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
    //        [newScrap setRotation:-lastBestRotation];
    //        [newScrap setScale:1];
    //    } completion:nil];
    
    [self saveToDisk];
    return newScrap;
}





-(void) addScrap:(MMScrapView*)scrap{
    @synchronized(scrapContainerView){
        [scrapContainerView addSubview:scrap];
    }
    [scrap setShouldShowShadow:[self isEditable]];
    [self saveToDisk];
}

-(BOOL) hasScrap:(MMScrapView*)scrap{
    return [[self scraps] containsObject:scrap];
}

/**
 * returns all subviews in back-to-front
 * order
 */
-(NSArray*) scraps{
    // we'll be calling this method quite often,
    // so don't create a new auto-released array
    // all the time. instead, just return our subview
    // array, so that if the caller just needs count
    // or to iterate on the main thread, we don't
    // spend unnecessary resources copying a potentially
    // long array.
    @synchronized(scrapContainerView){
        return scrapContainerView.subviews;
    }
}

#pragma mark - Pinch and Zoom

-(void) setFrame:(CGRect)frame{
    [super setFrame:frame];
    CGFloat _scale = frame.size.width / self.superview.frame.size.width;
    scrapContainerView.transform = CGAffineTransformMakeScale(_scale, _scale);
}

#pragma mark - Pan and Scale Scraps

/**
 * this is an important method to ensure that panning scraps and panning pages
 * don't step on each other.
 *
 * when panning, single touches are held as "possible" touches for both panning
 * gestures. once two possible touches exist in the pan gestures, then one of the
 * two gestures will own it.
 *
 * when a pan gesture takes ownership of a pair of touches, it needs to notify
 * the other pan gestures that it owns it. Since the PanPage gesture is owned
 * by the page and the PanScrap gesture is owned by the stack, we need these
 * delegate calls to be passed from gesture -> the gesture delegate -> page or stack
 * without causing an infinite loop of delegate calls.
 *
 * in this way, each gesture will notify its own delegate, either the stack or page.
 * the stack and page will notify each other *only* of touch ownerships from gestures
 * that they own. so the page will notify about PanPage ownership, and the stack
 * will notify of PanScrap ownership
 */
-(void) ownershipOfTouches:(NSSet*)touches isGesture:(UIGestureRecognizer*)gesture{
    [panGesture ownershipOfTouches:touches isGesture:gesture];
    if([gesture isKindOfClass:[MMPanAndPinchGestureRecognizer class]]){
        // only notify of our own gestures
        [self.delegate ownershipOfTouches:touches isGesture:gesture];
    }
}

-(BOOL) panScrapRequiresLongPress{
    return [self.delegate panScrapRequiresLongPress];
}

-(void) panAndScale:(MMPanAndPinchGestureRecognizer *)_panGesture{
    [[MMDebugDrawView sharedInstace] clear];
    
    [super panAndScale:_panGesture];
}

#pragma mark - JotViewDelegate



-(NSArray*) willAddElementsToStroke:(NSArray *)elements fromPreviousElement:(AbstractBezierPathElement*)_previousElement{
    NSArray* strokeElementsToDraw = [super willAddElementsToStroke:elements fromPreviousElement:_previousElement];
    
    if(![self.scraps count]){
        return strokeElementsToDraw;
    }
    
    NSMutableArray* strokesToCrop = [NSMutableArray arrayWithArray:strokeElementsToDraw];
    
    
    for(MMScrapView* scrap in [self.scraps reverseObjectEnumerator]){
        // find the bounding box of the scrap, so we can determine
        // quickly if they even possibly intersect
        UIBezierPath* scrapClippingPath = scrap.clippingPath;
        
        CGRect boundsOfScrap = scrapClippingPath.bounds;
        
        NSMutableArray* nextStrokesToCrop = [NSMutableArray array];
        
        // the first step is to loop over all of the strokes
        // to see where and if they intersect with our scraps.
        //
        // if they intersect, then we'll split that element into pieces
        // and add some pieces to the scrap and return the rest.
        AbstractBezierPathElement* previousElement = _previousElement;
        if(!previousElement){
            previousElement = [strokesToCrop firstObject];
        }
        for(AbstractBezierPathElement* element in strokesToCrop){
            if(!CGRectIntersectsRect(element.bounds, boundsOfScrap)){
                // if we don't intersect the bounds of a scrap, then we definitely
                // don't intersect it's path, so just add it to our return value
                // (which we'll check on other scraps too)
                [nextStrokesToCrop addObject:element];
            }else if([element isKindOfClass:[CurveToPathElement class]]){
                // ok, we intersect at least the bounds of the scrap, so check
                // to see if we intersect its path and if we should split it
                
                // create a simple uibezier path that represents just the path
                // of this single element
                UIBezierPath* strokePath = [element bezierPathSegment];
                
                // track which elements we should add to the scrap
                // instead of continue to chop and add to the page / other scrap
                NSMutableArray* elementsToAddToScrap = [NSMutableArray array];
                
                // now find out where this element intersects the scrap.
                // this return value will give us the paths of the intersection
                // and the difference, as well as the tvalues on our element
                // path (strokePath) that the intersections happen.
                //
                // this will let us calcualte how much the width/color/rotation
                // change during each split
                NSArray* redAndBlueSegments = nil;
                @try {
                    redAndBlueSegments = [UIBezierPath redAndGreenAndBlueSegmentsCreatedFrom:scrapClippingPath bySlicingWithPath:strokePath];
                }@catch (id exc) {
                    //        NSAssert(NO, @"need to log this");
                    NSLog(@"need to mail the paths");
                    
                    NSDateFormatter *dateFormater = [[NSDateFormatter alloc] init];
                    
                    [dateFormater setDateFormat:@"yyyy-MM-DD HH:mm:ss"];
                    NSString *convertedDateString = [dateFormater stringFromDate:[NSDate date]];
                    
                    NSString* textForEmail = @"Shapes in view:\n\n";
                    textForEmail = [textForEmail stringByAppendingFormat:@"scissor:\n%@\n\n\n", strokePath];
                    textForEmail = [textForEmail stringByAppendingFormat:@"shape:\n%@\n\n\n", scrapClippingPath];
                    
                    MFMailComposeViewController* controller = [[MFMailComposeViewController alloc] init];
                    [controller setMailComposeDelegate:self];
                    [controller setToRecipients:[NSArray arrayWithObject:@"adam.wulf@gmail.com"]];
                    [controller setSubject:[NSString stringWithFormat:@"Shape Clipping Test Case %@", convertedDateString]];
                    [controller setMessageBody:textForEmail isHTML:NO];
                    //        [controller addAttachmentData:imageData mimeType:@"image/png" fileName:@"screenshot.png"];
                    
                    if(controller){
                        UIViewController* rootController = [[[UIApplication sharedApplication] keyWindow] rootViewController];
                        [rootController presentViewController:controller animated:YES completion:nil];
                    }
                }
                
                NSArray* redSegments = [redAndBlueSegments firstObject]; // intersection
                NSArray* greenSegments = [redAndBlueSegments objectAtIndex:1]; // difference
                
                if(![redSegments count]){
                    // we can't make the same optimization for [.difference isEmpty],
                    // because the element needs to be transformed into the scrap's
                    // coordinate space no matter what. this means that we can't
                    // simply add the element to elementsToAddToScrap
                    //
                    // if the entire element lands in the difference (intersection is empty)
                    // then add the entire element to the page/other scraps to look at
                    [nextStrokesToCrop addObject:element];
                }else{
                    // take the difference of the drawn stroke, and send those elements
                    // to the next scrap beneath us to clip them smaller still.
                    // any unclipped elements will be passed back up to the page
                    // itself
                    for(DKUIBezierPathClippedSegment* segment in greenSegments){
                        [nextStrokesToCrop addObjectsFromArray:[segment convertToPathElementsFromColor:previousElement.color
                                                                                               toColor:element.color
                                                                                             fromWidth:previousElement.width
                                                                                               toWidth:element.width]];
                    }
                    // determine the tranlsation that we need to make on the path
                    // so that it's moved into the scrap's coordinate space
                    CGAffineTransform entireTransform = [scrap pageToScrapTransformWithPageOriginalUnscaledBounds:self.originalUnscaledBounds];
                    
                    // take the difference of the drawn stroke, and send those elements
                    // to the next scrap beneath us to clip them smaller still.
                    // any unclipped elements will be passed back up to the page
                    // itself
                    for(DKUIBezierPathClippedSegment* segment in redSegments){
                        [elementsToAddToScrap addObjectsFromArray:[segment convertToPathElementsFromColor:previousElement.color
                                                                                                  toColor:element.color
                                                                                                fromWidth:previousElement.width
                                                                                                  toWidth:element.width
                                                                                            withTransform:entireTransform
                                                                                                 andScale:scrap.scale]];
                    }
                }
                if([elementsToAddToScrap count]){
                    [scrap addElements:elementsToAddToScrap];
                }
            }else{
                [nextStrokesToCrop addObject:element];
            }
            
            previousElement = element;
        }
        
        strokesToCrop = nextStrokesToCrop;
    }
    
    // anything that's left over at this point
    // is fair game for to add to the page itself
    return strokesToCrop;
}


#pragma mark - MMRotationManagerDelegate

-(void) didUpdateAccelerometerWithRawReading:(CGFloat)currentRawReading{
    for(MMScrapView* scrap in self.scraps){
        [scrap didUpdateAccelerometerWithRawReading:-currentRawReading];
    }
}

#pragma mark - Polygon and Scrap builder

-(void) beginShapeAtPoint:(CGPoint)point{
    // send touch event to the view that
    // will display the drawn polygon line
    [shapeBuilderView clear];
    [shapeBuilderView addTouchPoint:point];
}

-(BOOL) continueShapeAtPoint:(CGPoint)point{
    // send touch event to the view that
    // will display the drawn polygon line
    if([shapeBuilderView addTouchPoint:point]){
        [self completeBuildingNewScrap];
        return NO;
    }
    return YES;
}

-(void) finishShapeAtPoint:(CGPoint)point{
    // send touch event to the view that
    // will display the drawn polygon line
    //
    // and also process the touches into the new
    // scrap polygon shape, and add that shape
    // to the page
    [shapeBuilderView addTouchPoint:point];
    [self completeBuildingNewScrap];
}

-(void) cancelShapeAtPoint:(CGPoint)point{
    // we've cancelled the polygon (possibly b/c
    // it was a pan/pinch instead), so clear
    // the drawn polygon and reset.
    [shapeBuilderView clear];
}

-(void) completeBuildingNewScrap{
    UIBezierPath* shape = [shapeBuilderView completeAndGenerateShape];
    [shapeBuilderView clear];
    if(shape.isPathClosed){
        UIBezierPath* shapePath = [shape copy];
        [shapePath applyTransform:CGAffineTransformMakeScale(1/self.scale, 1/self.scale)];
        [self addScrapWithPath:shapePath];
    }
}


#pragma mark - Scissors


-(void) beginScissorAtPoint:(CGPoint)point{
    // send touch event to the view that
    // will display the drawn polygon line
    [shapeBuilderView clear];
    [shapeBuilderView addTouchPoint:point];
}

-(BOOL) continueScissorAtPoint:(CGPoint)point{
    // send touch event to the view that
    // will display the drawn polygon line
    if([shapeBuilderView addTouchPoint:point]){
        [self completeScissorsCut];
        return NO;
    }
    return YES;
}

-(void) finishScissorAtPoint:(CGPoint)point{
    // send touch event to the view that
    // will display the drawn polygon line
    //
    // and also process the touches into the new
    // scrap polygon shape, and add that shape
    // to the page
    [shapeBuilderView addTouchPoint:point];
    [self completeScissorsCut];
}

-(void) cancelScissorAtPoint:(CGPoint)point{
    // we've cancelled the polygon (possibly b/c
    // it was a pan/pinch instead), so clear
    // the drawn polygon and reset.
    [shapeBuilderView clear];
}

-(void) completeScissorsCut{
    UIBezierPath* scissorPath = [shapeBuilderView completeAndGenerateShape];
    [scissorPath applyTransform:CGAffineTransformMakeScale(1/self.scale, 1/self.scale)];

    NSMutableArray* seenPaths = [NSMutableArray array];
    for(MMScrapView* scrap in [self.scraps reverseArray]){
        UIBezierPath* subshapePath = [[scrap clippingPath] copy];
        [subshapePath applyTransform:CGAffineTransformMake(1, 0, 0, -1, 0, self.originalUnscaledBounds.size.height)];
        
        BOOL isTopmost = YES;
        for(UIBezierPath* alreadySeenPath in seenPaths){
            NSArray* intersections = [alreadySeenPath findIntersectionsWithClosedPath:subshapePath andBeginsInside:nil];
            if([intersections count]){
                isTopmost = NO;
                break;
            }
        }
        
        if(isTopmost){
            NSArray* subshapes = [subshapePath uniqueSubshapesCreatedFromSlicingWithUnclosedPath:scissorPath];
            for(DKUIBezierPathShape* shape in subshapes){
                UIBezierPath* subshapePath = shape.fullPath;
                [self addScrapWithPath:subshapePath];
            }
            if([subshapes count]){
                @synchronized(scrapContainerView){
                    [scrap removeFromSuperview];
                }
            }
        }
        [seenPaths addObject:subshapePath];
    }
    [shapeBuilderView clear];
}


#pragma mark - Save and Load

/**
 * TODO: when our drawable view is set, our state
 * should already be 100% loaded, including scrap views
 *
 * ask super to set our drawable view, and we need to set
 * our scrap views
 */
-(void) setDrawableView:(JotView *)_drawableView{
    [super setDrawableView:_drawableView];
}

-(void) setEditable:(BOOL)isEditable{
    [super setEditable:isEditable];
    [scrapState setShouldShowShadows:isEditable];
}


-(BOOL) hasEditsToSave{
    return [super hasEditsToSave];
}

-(void) saveToDisk{
    
    // track if our back ground page has saved
    dispatch_semaphore_t sema1 = dispatch_semaphore_create(0);
    // track if all of our scraps have saved
    dispatch_semaphore_t sema2 = dispatch_semaphore_create(0);

    // save our backing page
    [super saveToDisk:^{
        dispatch_semaphore_signal(sema1);
    }];
    
    dispatch_async([MMScrapsOnPaperState importExportStateQueue], ^(void) {
        @autoreleasepool {
            [[scrapState immutableState] saveToDisk];
            dispatch_semaphore_signal(sema2);
        }
    });

    dispatch_async([MMScrappedPaperView concurrentBackgroundQueue], ^(void) {
        @autoreleasepool {
            dispatch_semaphore_wait(sema1, DISPATCH_TIME_FOREVER);
            dispatch_semaphore_wait(sema2, DISPATCH_TIME_FOREVER);
            dispatch_release(sema1);
            dispatch_release(sema2);
            if([self hasEditsToSave]){
                // our save failed. this may happen if we
                // call [saveToDisk] in very quick succession
                // so that the 1st call is still saving, and the
                // 2nd ends early b/c it knows the 1st is still going
                return;
            }
            [NSThread performBlockOnMainThread:^{
                [self.delegate didSavePage:self];
            }];
        }
    });
}

-(void) loadStateAsynchronously:(BOOL)async withSize:(CGSize)pagePixelSize andContext:(JotGLContext*)context{
    [super loadStateAsynchronously:async withSize:pagePixelSize andContext:context];
    [scrapState loadStateAsynchronously:async andMakeEditable:YES];
}

-(void) unloadState{
    [super unloadState];
    [[scrapState immutableState] saveToDisk];
    // unloading the scrap state will also remove them
    // from their superview (us)
    [scrapState unload];
}

-(BOOL) hasStateLoaded{
    return [super hasStateLoaded];
}

-(void) didLoadScrap:(MMScrapView*)scrap{
    @synchronized(scrapContainerView){
        [scrapContainerView addSubview:scrap];
    }
}

-(void) didLoadAllScrapsFor:(MMScrapsOnPaperState*)scrapState{
    // check to see if we've also loaded
    [self didLoadState:self.paperState];
}

/**
 * load any scrap previews, if applicable.
 * not sure if i'll just draw these into the
 * page preview or not
 */
-(void) loadCachedPreview{
    // make sure our thumbnail is loaded
    [super loadCachedPreview];
    // make sure our scraps' thumbnails are loaded
    [scrapState loadStateAsynchronously:YES andMakeEditable:NO];
}

-(void) unloadCachedPreview{
    // free our preview memory
    [super unloadCachedPreview];
    // free all scraps from memory too
    [scrapState unload];
}

#pragma mark - JotViewStateProxyDelegate

/**
 * TODO: only fire off these state methods
 * if we have also loaded state for our scraps
 * https://github.com/adamwulf/loose-leaf/issues/254
 */
-(void) didLoadState:(JotViewStateProxy*)state{
    if([self hasStateLoaded]){
        [NSThread performBlockOnMainThread:^{
            [self.delegate didLoadStateForPage:self];
        }];
    }
}

-(void) didUnloadState:(JotViewStateProxy *)state{
    [NSThread performBlockOnMainThread:^{
        [self.delegate didUnloadStateForPage:self];
    }];
}

#pragma mark - Paths

-(NSString*) scrapIDsPath{
    if(!scrapIDsPath){
        scrapIDsPath = [[[self pagesPath] stringByAppendingPathComponent:@"scrapIDs"] stringByAppendingPathExtension:@"plist"];
    }
    return scrapIDsPath;
}


#pragma mark - MFMailComposeViewControllerDelegate

- (void)mailComposeController:(MFMailComposeViewController*)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError*)error{
    UIViewController* rootController = [[[UIApplication sharedApplication] keyWindow] rootViewController];
    [rootController dismissViewControllerAnimated:YES completion:nil];
}


@end
