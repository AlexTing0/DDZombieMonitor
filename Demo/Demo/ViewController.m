//
//  ViewController.m
//  Demo
//
//  Created by Haisheng Ding on 2018/7/14.
//  Copyright © 2018年 AlexTing. All rights reserved.
//

#import "ViewController.h"
#import "DDZombieMonitor.h"
#import "DDBinaryImages.h"
#include <sys/sysctl.h>

@interface ZombieTest: NSObject

@property (nonatomic, strong)NSString *name;
@property (nonatomic, strong)NSString *text;

- (void)test;

@end

@implementation ZombieTest

- (instancetype)init {
    if (self = [super init]) {
        _name = @"name";
        _text = @"text";
    }
    return self;
}

- (void)test {
    NSLog(@"%@ %@", self.name, self.text);
}

@end

@interface ViewController ()

@property (nonatomic, assign)ZombieTest *zombieObj;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    //setup DDZombieMonitor
    void (^zombieHandle)(NSString *className, void *obj, NSString *selectorName, NSString *deallocStack, NSString *zombieStack) = ^(NSString *className, void *obj, NSString *selectorName, NSString *deallocStack, NSString *zombieStack) {
        NSString *zombeiInfo = [NSString stringWithFormat:@"ZombieInfo = \"detect zombie class:%@ obj:%p sel:%@\ndealloc stack:%@\nzombie stack:%@\"", className, obj, selectorName, deallocStack, zombieStack];
        NSLog(@"%@", zombeiInfo);
        
        NSString *binaryImages = [NSString stringWithFormat:@"BinaryImages = \"%@\"", [self binaryImages]];
        NSLog(@"%@", binaryImages);
    };
    [DDZombieMonitor sharedInstance].handle = zombieHandle;
    [[DDZombieMonitor sharedInstance] startMonitor];
    
    UIButton *button = [UIButton new];
    button.backgroundColor = [UIColor redColor];
    button.frame = CGRectMake(0, 64, 100, 40);
    [button addTarget:self action:@selector(buttonClick:) forControlEvents:UIControlEventTouchUpInside];
    [button setTitle:@"触发zombie" forState:UIControlStateNormal];
    [self.view addSubview:button];
    
    ZombieTest *zombieObj = [ZombieTest new];
    self.zombieObj = zombieObj;
    [self.zombieObj test];
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)buttonClick:(id)sender {
    [self.zombieObj test];
}


- (NSString*)binaryImages {
    NSArray *binaryImages = [DDBinaryImages binaryImages];
    NSMutableString *binaryImagesStr = [NSMutableString new];
    
    NSString *osVersion = [UIDevice currentDevice].systemVersion;
    NSString *ctlKey = @"kern.osversion";
    NSString *buildValue;
    size_t size = 0;
    if (sysctlbyname([ctlKey UTF8String], NULL, &size, NULL, 0) != -1){
        char *machine = calloc( 1, size );
        sysctlbyname([ctlKey UTF8String], machine, &size, NULL, 0);
        buildValue = [NSString stringWithCString:machine encoding:[NSString defaultCStringEncoding]];
        free(machine);
    }
    
    [binaryImagesStr appendFormat:@"{\nOS Version:%@ (%@)\n", osVersion, buildValue];
    for (NSString *image in binaryImages) {
        [binaryImagesStr appendString:image];
        [binaryImagesStr appendString:@"\n"];
    }
    [binaryImagesStr appendString:@"}"];
    return [binaryImagesStr copy];
}

@end
