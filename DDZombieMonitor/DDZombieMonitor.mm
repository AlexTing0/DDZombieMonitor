////  HYZombieDetetor.m
//  DDZombieDetector
//
//  Created by Alex Ting on 2018/7/14.
//  Copyright © 2018年 Alex. All rights reserved.
//

#if __has_feature(objc_arc)
#error This file must be compiled without ARC. Use -fno-objc-arc flag.
#endif

#import "DDZombieMonitor.h"

#import <objc/runtime.h>
#import <malloc/malloc.h>
#import <UIKit/UIKit.h>

#import "queue.h"
#import "DDZombieMonitor+Private.h"
#import "NSObject+DDZombieDetector.h"
#import "DDZombie.h"
#import "DDThreadStack.h"

static NSInteger kDefaultMaxOccupyMemorySize = 10 * 1024 * 1024;
static uint32_t  kEstimateZombieObjectSize = 64; //对象平均大小64Byte
static uint32_t  kEstimateDeallocStackSize = 91; //释放栈平均大小，释放栈平均depth为15，ARM64下栈大小为15*5，DDThreadStack大小16Byte

/**
 *X个item时组件占用内存大小估算
 *总内存=queue内存+对象内存+释放栈内存
 *total memory = ：X * 8 + X * (75 + 16 + 64)
 *
 */
 

void replaceSelectorWithSelector(Class aCls,
                                 SEL selector,
                                 SEL replacementSelector) {
    Method replacementSelectorMethod = class_getInstanceMethod(aCls, replacementSelector);
    Class classEntityToEdit = aCls;
    class_replaceMethod(classEntityToEdit,
                        selector,
                        method_getImplementation(replacementSelectorMethod),
                        method_getTypeEncoding(replacementSelectorMethod));
}


@implementation DDZombieMonitor
{
    struct DSQueue *_delayFreeQueue;
    NSUInteger _occupyMemorySize; //占用内存大小，包括延迟释放对象内存大小和释放栈大小
    BOOL _isInDetecting;
    CFMutableSetRef _customRegisteredClasses;
    NSSet<NSString*> *_whiteList;
    NSSet<NSString*> *_blackList;
    NSSet<NSString*> *_filterList;
}

@dynamic whiteList;
@dynamic blackList;
@dynamic filterList;

+ (instancetype)sharedInstance {
    static DDZombieMonitor *s_instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        s_instance = [DDZombieMonitor new];
    });
    return s_instance;
}

- (instancetype)init {
    if (self = [super init]) {
        self.crashWhenDetectedZombie = YES;
        self.maxOccupyMemorySize = kDefaultMaxOccupyMemorySize;
        self.traceDeallocStack = YES;
        self.detectStrategy = DDZombieDetectStrategyCustomObjectOnly;
        replaceSelectorWithSelector([NSObject class], @selector(hy_originalDealloc), sel_registerName("dealloc"));
    }
    return self;
}

- (void)dealloc {
    [self stopMonitor];
    [super dealloc];
}

- (void)startMonitor {
    @synchronized(self) {
        if (_isInDetecting) {
            return;
        }
        int32_t itemEstimateSize = kEstimateZombieObjectSize;
        if (_traceDeallocStack) {
            itemEstimateSize += kEstimateDeallocStackSize;
        }
        int32_t queueCapacity = (int32_t)(self.maxOccupyMemorySize / itemEstimateSize + 1023) / 1024 * 1024; //align to 1024
        _delayFreeQueue = ds_queue_create(queueCapacity);
        _isInDetecting = YES;
        [self getCustomClass];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(memoryWarningNotificationHandle:) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
        replaceSelectorWithSelector([NSObject class], sel_registerName("dealloc"), @selector(hy_newDealloc));
    }
}
- (void)stopMonitor {
    @synchronized(self) {
        if (!_isInDetecting) {
            return;
        }
        replaceSelectorWithSelector([NSObject class], sel_registerName("dealloc"), @selector(hy_originalDealloc));
        void * item = ds_queue_try_get(_delayFreeQueue);
        while (item) {
            [self freeZombieObject:item];
            item = ds_queue_try_get(_delayFreeQueue);
        }
        _isInDetecting = NO;
        ds_queue_close(_delayFreeQueue);
        ds_queue_free(_delayFreeQueue);
        _delayFreeQueue = NULL;
        CFRelease(_customRegisteredClasses);
        _customRegisteredClasses = NULL;
        [[NSNotificationCenter defaultCenter] removeObserver:self];
    }
}

- (void)newDealloc:(__unsafe_unretained id)obj {
    if ([self shouldDetect:[obj class]]) {
        void *p = (__bridge void *)obj;
        size_t memSize = malloc_size(p);
        if (memSize >= [DDZombie zombieInstanceSize]) {//有足够的空间才覆盖
            
            Class origClass = object_getClass(obj);
            
            ///析构对象
            objc_destructInstance(obj);
            
            ///填充0x55能稍微提升一些crash率
            memset(p, 0x55, memSize);
            memset(p, 0x00, [DDZombie zombieInstanceSize]);
            
            ///把我们自己的类的isa复制过去
            Class c = [DDZombie zombieIsa];
            memcpy(obj, &c, sizeof(void*));
            
            DDZombie* zombie = (DDZombie*)p;
            
            zombie.realClass = origClass;
            
            if (_traceDeallocStack) {
                DDThreadStack *stack = hy_getCurrentStack();
                zombie.threadStack = stack;
                memSize += stack->occupyMemorySize();
            }
            
            [self freeMemoryIfNeed];
            
            __sync_fetch_and_add(&_occupyMemorySize, (int)memSize);
            void *item = ds_queue_put_pop_first_item_if_need(_delayFreeQueue, p);
            if (item) {
                [self freeZombieObject:item];
            }
        } else {
            [obj performSelector:@selector(hy_originalDealloc)];
        }
    } else {
        [obj performSelector:@selector(hy_originalDealloc)];
    }
}

- (BOOL)shouldDetect:(Class)aClass {
    if (aClass == Nil) {
        return NO;
    }
    BOOL bShouldDetect = NO;
    
    @autoreleasepool {
        NSString *className = NSStringFromClass(aClass);
        if ([_filterList containsObject:className]) {
            return NO;
        }
        
        switch (_detectStrategy) {
            case DDZombieDetectStrategyCustomObjectOnly:
                bShouldDetect =  CFSetContainsValue(_customRegisteredClasses, (__bridge void*)aClass);
                break;
            case DDZombieDetectStrategyWhitelist:
                bShouldDetect = [_whiteList containsObject:className];
                break;
            case DDZombieDetectStrategyBlacklist:
                bShouldDetect = ![_blackList containsObject:className];
                break;
            case DDZombieDetectStrategyAll:
                bShouldDetect = YES;
                break;
            default:
                break;
        }
    }
    
    return bShouldDetect;
}

- (void)freeZombieObject:(void*)obj {
    DDZombie* zombieObject = (__bridge DDZombie*)obj;
    size_t threadStackMemSize = 0;
    if (zombieObject.threadStack) {
        threadStackMemSize = zombieObject.threadStack->occupyMemorySize();
        delete zombieObject.threadStack;
        zombieObject.threadStack = NULL;
    }
    size_t zombieObjectSize = malloc_size(obj);
    size_t total_size = threadStackMemSize + zombieObjectSize;
    free(obj);
    __sync_fetch_and_sub(&_occupyMemorySize, (int)(total_size));
}

- (void)getCustomClass {
    _customRegisteredClasses = CFSetCreateMutable(NULL, 0, NULL);
    unsigned int classCount=0;
    const char** classNames=objc_copyClassNamesForImage([[NSBundle mainBundle] executablePath].UTF8String,&classCount);
    if (classNames) {
        for (unsigned int i = 0; i < classCount; i++) {
            const char *className = classNames[i];
            Class aClass=objc_getClass(className);
            
            CFSetAddValue(_customRegisteredClasses, (__bridge const void *)(aClass));
        }
        //内存释放，参考：http://opensource.apple.com//source/objc4/objc4-437.3/test/weak.m
        free(classNames);
    }
}
    
- (void)freeMemoryIfNeed {
    if (_occupyMemorySize < _maxOccupyMemorySize) {
        return;
    }
    
    @synchronized(self) {
        if (_occupyMemorySize >= _maxOccupyMemorySize) {
            [self forceFreeMemory];
        }
    }
}

- (void)forceFreeMemory {
    uint32_t freeCount = 0;
    int max_free_count_one_time = ds_queue_length(_delayFreeQueue) / 5;
    void * item = ds_queue_try_get(_delayFreeQueue);
    while (item && freeCount < max_free_count_one_time) {
        [self freeZombieObject:item];
        item = ds_queue_try_get(_delayFreeQueue);
        ++freeCount;
    }
}

- (void)memoryWarningNotificationHandle:(NSNotification*)notification {
    [self forceFreeMemory];
}

#pragma mark - getter & setter

- (NSArray<NSString*>*)whiteList {
    return [_whiteList allObjects];
}

- (void)setWhiteList:(NSArray<NSString *> *)whiteList {
    _whiteList = [[NSSet alloc] initWithArray:whiteList];
}

- (NSArray<NSString*>*)blackList {
    return [_blackList allObjects];
}

- (void)setBlackList:(NSArray<NSString *> *)blackList {
    _blackList = [[NSSet alloc] initWithArray:blackList];
}

- (NSArray<NSString*>*)filterList {
    return [_filterList allObjects];
}

- (void)setFilterList:(NSArray<NSString *> *)filterList {
    _filterList = [[NSSet alloc] initWithArray:filterList];
}


@end
