////  HYZombieDetetor.h
//  DDZombieDetector
//
//  Created by Alex Ting on 2018/7/14.
//  Copyright © 2018年 Alex. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, DDZombieDetectStrategy) {
    DDZombieDetectStrategyCustomObjectOnly = 0, //只监控自定义对象, 默认使用该策略
    DDZombieDetectStrategyBlacklist = 1, //使用黑名单
    DDZombieDetectStrategyWhitelist = 2, //使用白名单
    DDZombieDetectStrategyAll = 3, //监控所有对象，强制过滤类除外
};

/**
 * 为提升性能，监控属性不是线程安全，需要在start之前设置
 * 监控原理：swizzling [NSObject dealloc]方法，dealloc时只调用析构，不调用free，同时把isa指针指向HYZombie，通过消息转发机制捕捉zombie对象
 * 内存占用：延迟free和对象释放栈占用内存比较大，可以通过maxOccupyMemorySize设置最大内存，当收到memoryWarning或超出maxOccupyMemorySize后，通过FIFO机制释放对象，由于访问局部性，所以通过FIFO释放对象对捕捉效果影响不大
 */
@interface DDZombieMonitor : NSObject

@property (nonatomic, assign) BOOL crashWhenDetectedZombie; //监测到zombie时是否触发crash，默认YES
@property (nonatomic, assign) NSInteger maxOccupyMemorySize; //组件最大占用内存大小，包括延迟释放内存大小和释放栈内存大小，默认10M
@property (nonatomic, assign) BOOL traceDeallocStack; //是否记录dealloc栈，默认YES
@property (nonatomic, assign) DDZombieDetectStrategy detectStrategy; //监控策略，默认DDZombieDetectStrategyCustomObjectOnly
@property (nonatomic, copy) NSArray<NSString*> *blackList; //黑名单，DDZombieDetectStrategyBlacklist时生效
@property (nonatomic, copy) NSArray<NSString*> *whiteList; //白名单，DDZombieDetectStrategyWhitelist生效
@property (nonatomic, copy) NSArray<NSString*> *filterList; //强制过滤类，不受监控策略影响，主要用于过滤频繁创建的对象，比如log

/**
 * handle，监测到zombie时调用
 * @param className zombie对象名
 * @param obj zombie对象地址
 * @param selectorName selector
 * @param deallocStack zombie对象释放栈，格式:{\ntid:xxx\nstack:[xxx,xxx,xxx]\n},栈为未符号化的函数地址
 * @param zombieStack  zombie对象调用栈，格式:{\ntid:xxx\nstack:[xxx,xxx,xxx]\n},栈为未符号化的函数地址
 */
@property (nonatomic, strong) void (^handle)(NSString *className, void* obj, NSString *selectorName, NSString* deallocStack, NSString *zombieStack);

+ (instancetype)sharedInstance;
- (void)startMonitor;
- (void)stopMonitor;


@end
