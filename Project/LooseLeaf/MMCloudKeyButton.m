//
//  MMCloudKeyButton.m
//  LooseLeaf
//
//  Created by Adam Wulf on 9/9/14.
//  Copyright (c) 2014 Milestone Made, LLC. All rights reserved.
//

#import "MMCloudKeyButton.h"
#import "MMRotatingKeyDemoLayer.h"
#import "MMBrokenCloudLayer.h"
#import "MMRotationManager.h"
#import "MMCloudErrorIconLayer.h"
#import "UIView+Animations.h"
#import "UIView+Debug.h"


@implementation MMCloudKeyButton {
    MMRotatingKeyDemoLayer* needLoginView;
    NSTimer* bounceTimer;
    MMCloudErrorIconLayer* brokenCloud;
}

- (id)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        needLoginView = [[MMRotatingKeyDemoLayer alloc] initWithFrame:CGRectMake(0, 0, frame.size.width, frame.size.height)];
        [self.layer addSublayer:needLoginView];
        [self addTarget:self action:@selector(didTapButton) forControlEvents:UIControlEventTouchUpInside];
    }
    return self;
}

- (BOOL)isShowingKey {
    return !needLoginView.isFlipped;
}

- (void)flipImmediatelyToCloud {
    if ([self isShowingKey]) {
        [needLoginView flipWithoutAnimation];
    }
    if (brokenCloud) {
        needLoginView.opacity = 1.0;
        [brokenCloud removeFromSuperlayer];
        brokenCloud = nil;
    }
}

- (void)flipAnimatedToKeyWithCompletion:(void (^)())completion {
    if (![self isShowingKey]) {
        [needLoginView bounceAndFlipWithCompletion:completion];
    } else {
        if (completion)
            completion();
    }
}

- (void)animateToBrokenCloud {
    brokenCloud = [[MMCloudErrorIconLayer alloc] initWithFrame:self.bounds];
    [self.layer addSublayer:brokenCloud];

    brokenCloud.opacity = 1.0;
    needLoginView.opacity = 0.0;

    // animate:
    CABasicAnimation* opacityForBreak = [CABasicAnimation animationWithKeyPath:@"opacity"];
    opacityForBreak.fromValue = @(0.0);
    opacityForBreak.toValue = @(1.0);
    opacityForBreak.duration = .3;

    CGAffineTransform currTransform = self.transform;
    self.transform = CGAffineTransformIdentity;

    [CATransaction begin];
    [brokenCloud addAnimation:opacityForBreak forKey:@"opacity"];

    CGRect selfBounds = self.bounds;
    CGPoint updatedAnchorPoint = [brokenCloud centerOfErrorCircle];
    updatedAnchorPoint.x /= selfBounds.size.width;
    updatedAnchorPoint.y /= selfBounds.size.height;
    [UIView setAnchorPoint:updatedAnchorPoint forView:self];
    [CATransaction commit];

    self.transform = currTransform;
}

- (void)setupTimer {
    if (!bounceTimer) {
        bounceTimer = [NSTimer scheduledTimerWithTimeInterval:3.5 target:self selector:@selector(bounceLightly) userInfo:nil repeats:YES];
        [self bounceLightly];
    }
}

- (void)tearDownTimer {
    [bounceTimer invalidate];
    bounceTimer = nil;
}

- (void)didTapButton {
    [self tearDownTimer];
    [needLoginView bounceAndFlipWithCompletion:nil];
    self.enabled = NO;
}

- (void)bounceLightly {
    UIInterfaceOrientation orientation = [[MMRotationManager sharedInstance] lastBestOrientation];

    [UIView animateWithDuration:.08 animations:^{
        self.transform = CGAffineTransformScale(CGAffineTransformMakeRotation([self idealRotationForOrientation:orientation]), 0.9, 0.9);
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:.14 animations:^{
            self.transform = CGAffineTransformScale(CGAffineTransformMakeRotation([self idealRotationForOrientation:orientation]), 1.1, 1.1);
        } completion:^(BOOL finished) {
            [UIView animateWithDuration:.12 animations:^{
                self.transform = CGAffineTransformMakeRotation([self idealRotationForOrientation:orientation]);
            } completion:nil];
        }];
    }];
}

#pragma mark - Rotation

- (CGFloat)idealRotationForOrientation:(UIInterfaceOrientation)orientation {
    CGFloat visiblePhotoRotation = 0;
    if (orientation == UIInterfaceOrientationLandscapeRight) {
        visiblePhotoRotation = M_PI / 2;
    } else if (orientation == UIInterfaceOrientationPortraitUpsideDown) {
        visiblePhotoRotation = M_PI;
    } else if (orientation == UIInterfaceOrientationLandscapeLeft) {
        visiblePhotoRotation = -M_PI / 2;
    } else {
        visiblePhotoRotation = 0;
    }
    return visiblePhotoRotation;
}

- (void)updateInterfaceTo:(UIInterfaceOrientation)orientation animated:(BOOL)animated {
    if (animated) {
        [UIView animateWithDuration:.2 animations:^{
            self.transform = CGAffineTransformMakeRotation([self idealRotationForOrientation:orientation]);
        }];
    } else {
        self.transform = CGAffineTransformMakeRotation([self idealRotationForOrientation:orientation]);
    }
}

@end
