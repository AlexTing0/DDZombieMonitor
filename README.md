# ZombieMonitor
自动监控iOS Zombie问题，并且提供Zombie对象类名、selector、释放栈信息，开启监控后对cpu影响很小(不到0.2%)，支持设置组件最大占用内存，具体介绍请查看[文章](https://github.com/AlexTing0/Monitor_Zombie_in_iOS)

# Features
- 主动监控Zombie问题，并且提供Zombie对象类名、selector、释放栈信息
- 支持不同监控策略，包括App内自定义类、白名单、黑名单、所有对象
- 支持设置最大占用内存
- 组件在收到内存告警或超过最大内存时，通过FIFO算法释放部分对象

# Usage
## Basic

```
    //setup DDZombieMonitor
    void (^zombieHandle)(NSString *className, void *obj, NSString *selectorName, NSString *deallocStack, NSString *zombieStack) = ^(NSString *className, void *obj, NSString *selectorName, NSString *deallocStack, NSString *zombieStack) {
        NSString *zombeiInfo = [NSString stringWithFormat:@"ZombieInfo = \"detect zombie class:%@ obj:%p sel:%@\ndealloc stack:%@\nzombie stack:%@\"", className, obj, selectorName, deallocStack, zombieStack];
        NSLog(@"%@", zombeiInfo);
        
        NSString *binaryImages = [NSString stringWithFormat:@"BinaryImages = \"%@\"", [self binaryImages]];
        NSLog(@"%@", binaryImages);
    };
    [DDZombieMonitor sharedInstance].handle = zombieHandle;
    [[DDZombieMonitor sharedInstance] startMonitor];
```

## 监控策略

```
typedef NS_ENUM(NSInteger, DDZombieDetectStrategy) {
    DDZombieDetectStrategyCustomObjectOnly = 0, //只监控App内自定义类, 默认使用该策略
    DDZombieDetectStrategyBlacklist = 1, //使用黑名单
    DDZombieDetectStrategyWhitelist = 2, //使用白名单
    DDZombieDetectStrategyAll = 3, //监控所有对象，强制过滤类除外
};
```

## 符号化
释放栈和zombie栈只保存了函数地址，格式如下：
```
dealloc stack:{
tid:1027
stack:[0x0000000100047534,0x000000010004b2e4,0x00000001000498b0,0x000000018e9bdf9c,0x000000018e9bdb78,0x000000018e9c43f8,0x000000018e9c1894,0x000000018ea332fc,0x000000018ec3b8b4,0x000000018ec412a8,0x000000018ec55de0,0x000000018ec3e53c,0x000000018a437884,0x000000018a4376f0,0x000000018a437aa0,0x000000018883d424,0x000000018883cd94,0x000000018883a9a0,0x000000018876ad94,0x000000018ea2845c,0x000000018ea23130,0x000000010004b374,0x000000018777959c,]
}
```

可以使用Symbolicating.py脚本进行符号化，把zombeiInfo和binaryImages保存到crash_attach.log文件中，并且把dSYM文件和crash_attach.log放在同一个目录，比如crash，替换脚本中Demo为自己对工程名，运行下面命令，运行完后将在crash目录生吃zombie_info.log文件
```
python Symbolicating.py 'crash'
```
zombie_info.log文件包含zombie详细信息：

```
Zombie Info

Zombie Class Name: ZombieTest
Zombie Object Address: 0x17003f720
Selector Name: retain

Dealloc Stack:
tid:1027
0    Demo                          0x0000000100047534 -[DDZombieMonitor newDealloc:] (in Demo) (DDZombieMonitor.mm:151)
1    Demo                          0x000000010004b2e4 -[NSObject(DDZombieDetector) hy_newDealloc] (in Demo) (NSObject+DDZombieDetector.m:19)
2    Demo                          0x00000001000498b0 -[ViewController viewDidLoad] (in Demo) (ViewController.m:71)
3    UIKit                         0x000000018e9bdf9c -[UIViewController loadViewIfRequired] (in UIKit) + 1036
4    UIKit                         0x000000018e9bdb78 -[UIViewController view] (in UIKit) + 28
5    UIKit                         0x000000018e9c43f8 -[UIWindow addRootViewControllerViewIfPossible] (in UIKit) + 76
6    UIKit                         0x000000018e9c1894 -[UIWindow _setHidden:forced:] (in UIKit) + 272
7    UIKit                         0x000000018ea332fc -[UIWindow makeKeyAndVisible] (in UIKit) + 48
8    UIKit                         0x000000018ec3b8b4 -[UIApplication _callInitializationDelegatesForMainScene:transitionContext:] (in UIKit) + 3632
9    UIKit                         0x000000018ec412a8 -[UIApplication _runWithMainScene:transitionContext:completion:] (in UIKit) + 1684
10   UIKit                         0x000000018ec55de0 __84-[UIApplication _handleApplicationActivationWithScene:transitionContext:completion:]_block_invoke.3151 (in UIKit) + 48
11   UIKit                         0x000000018ec3e53c -[UIApplication workspaceDidEndTransaction:] (in UIKit) + 168
12   FrontBoardServices            0x000000018a437884 __FBSSERIALQUEUE_IS_CALLING_OUT_TO_A_BLOCK__ (in FrontBoardServices) + 36
13   FrontBoardServices            0x000000018a4376f0 -[FBSSerialQueue _performNext] (in FrontBoardServices) + 176
14   FrontBoardServices            0x000000018a437aa0 -[FBSSerialQueue _performNextFromRunLoopSource] (in FrontBoardServices) + 56
15   CoreFoundation                0x000000018883d424 __CFRUNLOOP_IS_CALLING_OUT_TO_A_SOURCE0_PERFORM_FUNCTION__ (in CoreFoundation) + 24
16   CoreFoundation                0x000000018883cd94 __CFRunLoopDoSources0 (in CoreFoundation) + 540
17   CoreFoundation                0x000000018883a9a0 __CFRunLoopRun (in CoreFoundation) + 744
18   CoreFoundation                0x000000018876ad94 CFRunLoopRunSpecific (in CoreFoundation) + 424
19   UIKit                         0x000000018ea2845c -[UIApplication _run] (in UIKit) + 652
20   UIKit                         0x000000018ea23130 UIApplicationMain (in UIKit) + 208
21   Demo                          0x000000010004b374 main (in Demo) (main.m:14)
22   libdyld.dylib                 0x000000018777959c start (in libdyld.dylib) + 4

Zombie Call Stack:
tid:1027
0    Demo                          0x0000000100048a84 -[DDZombie retain] (in Demo) (DDZombie.mm:67)
1    Demo                          0x0000000100049c94 -[ViewController buttonClick:] (in Demo) (ViewController.m:80)
2    UIKit                         0x000000018e9f30ec -[UIApplication sendAction:to:from:forEvent:] (in UIKit) + 96
3    UIKit                         0x000000018e9f306c -[UIControl sendAction:to:forEvent:] (in UIKit) + 80
4    UIKit                         0x000000018e9dd5e0 -[UIControl _sendActionsForEvents:withEvent:] (in UIKit) + 440
5    UIKit                         0x000000018e9f2950 -[UIControl touchesEnded:withEvent:] (in UIKit) + 576
6    UIKit                         0x000000018e9f246c -[UIWindow _sendTouchesForEvent:] (in UIKit) + 2480
7    UIKit                         0x000000018e9ed804 -[UIWindow sendEvent:] (in UIKit) + 3192
8    UIKit                         0x000000018e9be418 -[UIApplication sendEvent:] (in UIKit) + 340
9    UIKit                         0x000000018f1b7f64 __dispatchPreprocessedEventFromEventQueue (in UIKit) + 2400
10   UIKit                         0x000000018f1b26c0 __handleEventQueue (in UIKit) + 4268
11   UIKit                         0x000000018f1b2aec __handleHIDEventFetcherDrain (in UIKit) + 148
12   CoreFoundation                0x000000018883d424 __CFRUNLOOP_IS_CALLING_OUT_TO_A_SOURCE0_PERFORM_FUNCTION__ (in CoreFoundation) + 24
13   CoreFoundation                0x000000018883cd94 __CFRunLoopDoSources0 (in CoreFoundation) + 540
14   CoreFoundation                0x000000018883a9a0 __CFRunLoopRun (in CoreFoundation) + 744
15   CoreFoundation                0x000000018876ad94 CFRunLoopRunSpecific (in CoreFoundation) + 424
16   GraphicsServices              0x000000018a1d4074 GSEventRunModal (in GraphicsServices) + 100
17   UIKit                         0x000000018ea23130 UIApplicationMain (in UIKit) + 208
18   Demo                          0x000000010004b374 main (in Demo) (main.m:14)
19   libdyld.dylib                 0x000000018777959c start (in libdyld.dylib) + 4
```
