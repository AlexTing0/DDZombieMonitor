////  HYBinaryImages.m
//  DDZombieDetector
//
//  Created by Alex Ting on 2018/7/14.
//  Copyright © 2018年 Alex. All rights reserved.
//

#import "DDBinaryImages.h"
#import <mach-o/dyld.h>

@implementation DDBinaryImages

uintptr_t ksdl_firstCmdAfterHeader(const struct mach_header* const header)
{
    switch(header->magic)
    {
        case MH_MAGIC:
        case MH_CIGAM:
            return (uintptr_t)(header + 1);
        case MH_MAGIC_64:
        case MH_CIGAM_64:
            return (uintptr_t)(((struct mach_header_64*)header) + 1);
        default:
            // Header is corrupt
            return 0;
    }
}

+ (NSMutableArray*)binaryImages {
    NSString * architecture = nil;
#if defined(__arm64__)
    architecture = @"arm64";
#elif defined(__arm__)
    architecture = @"armv7";
#elif defined(__x86_64__)
    architecture = @"x86_64";
#elif defined(__i386__)
    architecture = @"i386";
#endif
    
    NSMutableArray *allLoadedImage = [NSMutableArray new];
    const uint32_t imageCount = _dyld_image_count();
    for (uint32_t i = 0 ;i < imageCount; ++ i) {
        const struct mach_header* header = _dyld_get_image_header(i);
        if(header == NULL)
        {
            continue;
        }
        
        NSString* imageFullName = [NSString stringWithUTF8String:_dyld_get_image_name(i)];
        
        NSRange range = [imageFullName rangeOfString:@"/" options:NSBackwardsSearch];
        if(range.location == NSNotFound || range.location == imageFullName.length) {
            continue;
        }
        
        NSString* imageName = [imageFullName substringFromIndex:range.location+1];
        
        uintptr_t cmdPtr = ksdl_firstCmdAfterHeader(header);
        if(cmdPtr == 0)
        {
            continue;
        }
        
        // Look for the TEXT segment to get the image size.
        // Also look for a UUID command.
        uint64_t imageSize = 0;
        uint64_t imageVmAddr = 0;
        NSString* uuidStr = nil;
        
        for(uint32_t iCmd = 0; iCmd < header->ncmds; iCmd++)
        {
            struct load_command* loadCmd = (struct load_command*)cmdPtr;
            switch(loadCmd->cmd)
            {
                case LC_SEGMENT:
                {
                    struct segment_command* segCmd = (struct segment_command*)cmdPtr;
                    if(strcmp(segCmd->segname, SEG_TEXT) == 0)
                    {
                        imageSize = segCmd->vmsize;
                        imageVmAddr = segCmd->vmaddr;
                    }
                    break;
                }
                case LC_SEGMENT_64:
                {
                    struct segment_command_64* segCmd = (struct segment_command_64*)cmdPtr;
                    if(strcmp(segCmd->segname, SEG_TEXT) == 0)
                    {
                        imageSize = segCmd->vmsize;
                        imageVmAddr = segCmd->vmaddr;
                    }
                    break;
                }
                case LC_UUID:
                {
                    struct uuid_command* uuidCmd = (struct uuid_command*)cmdPtr;
                    uint8_t *uuid = uuidCmd->uuid;
                    uuidStr = [NSString stringWithFormat:@"%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X",
                                uuid[0], uuid[1], uuid[2], uuid[3],
                                uuid[4], uuid[5], uuid[6], uuid[7],
                                uuid[8], uuid[9], uuid[10], uuid[11],
                                uuid[12], uuid[13], uuid[14], uuid[15]];
                    break;
                }
            }
            cmdPtr += loadCmd->cmdsize;
        }
        
        NSString *imageInfo = [NSString stringWithFormat:@"0x%lx - 0x%lx %@ %@ <%@> %@", (uintptr_t)header, (uintptr_t)((uintptr_t)header + imageSize -1), imageName, architecture, uuidStr, imageFullName];
        [allLoadedImage addObject:imageInfo];
    }
    return allLoadedImage;
}

@end
