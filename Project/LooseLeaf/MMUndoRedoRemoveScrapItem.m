//
//  MMUndoRedoRemoveScrapItem.m
//  LooseLeaf
//
//  Created by Adam Wulf on 7/5/14.
//  Copyright (c) 2014 Milestone Made, LLC. All rights reserved.
//

#import "MMUndoRedoRemoveScrapItem.h"
#import "MMUndoablePaperView.h"

@implementation MMUndoRedoRemoveScrapItem{
    NSDictionary* propertiesWhenRemoved;
}

+(id) itemForPage:(MMUndoablePaperView*)_page andScrap:(MMScrapView*)scrap{
    return [[MMUndoRedoRemoveScrapItem alloc] initForPage:_page andScrap:scrap];
}

-(id) initForPage:(MMUndoablePaperView*)_page andScrap:(MMScrapView*)scrap{
    __weak MMUndoablePaperView* weakPage = _page;
    propertiesWhenRemoved = [scrap propertiesDictionary];
    if(self = [super initWithUndoBlock:^{
        [weakPage addScrap:scrap];
        [scrap setPropertiesDictionary:propertiesWhenRemoved];
    } andRedoBlock:^{
        [weakPage removeScrap:scrap];
    } forPage:_page]){
        // noop
    };
    return self;
}


#pragma mark - Serialize

-(NSDictionary*) asDictionary{
    return [NSDictionary dictionary];
}

-(id) initFromDictionary:(NSDictionary*)dict forPage:(MMUndoablePaperView*)_page{
    if(self = [self initForPage:_page andScrap:nil]){
        canUndo = [[dict objectForKey:@"canUndo"] boolValue];
    }
    return self;
}

@end