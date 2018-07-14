////  NSObject+DDZombieDetector.h
//  DDZombieDetector
//
//  Created by Alex Ting on 2018/7/14.
//  Copyright © 2018年 Alex. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSObject (DDZombieDetector)

-(void)hy_originalDealloc;
-(void)hy_newDealloc;

@end
