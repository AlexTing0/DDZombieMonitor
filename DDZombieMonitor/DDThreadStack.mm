////  DDThreadStack.m
//  DDZombieDetector
//
//  Created by Alex Ting on 2018/7/14.
//  Copyright © 2018年 Alex. All rights reserved.
//

#import "DDThreadStack.h"

#import <mach/mach.h>
#import <execinfo.h>
#include <pthread.h>

#define HY_THREAD_STACK_MAX_DEPTH (63 + HY_THREAD_STACK_FILTER_DEPTH)
#define HY_THREAD_STACK_FILTER_DEPTH 2 //过滤最上面两层栈

#if defined(__arm64__)
#define HY_SIZE_PER_STACK (sizeof(char) * 5) //40bits

#else

#define HY_SIZE_PER_STACK (sizeof(vm_address_t)) //non special handle
#endif //define __arm64__

#define HY_SIZE_FOR_STACK_DEPTH(depth) (HY_SIZE_PER_STACK * depth)

DDThreadStack::DDThreadStack()
{
    _tid = 0;
    _depth = 0;
    _stack = nullptr;
}

DDThreadStack::~DDThreadStack()
{
    if (_stack) {
        free(_stack);
        _stack = nullptr;
    }
}

void DDThreadStack::fetchCurrentStack()
{
    vm_address_t thread_stack[HY_THREAD_STACK_MAX_DEPTH];
    uint32_t depth = backtrace((void**)&thread_stack, HY_THREAD_STACK_MAX_DEPTH);
    _depth = depth - HY_THREAD_STACK_FILTER_DEPTH;
    if (depth < HY_THREAD_STACK_FILTER_DEPTH || depth > HY_THREAD_STACK_MAX_DEPTH) {
        depth = _depth = 0;
    }
    size_t stack_mem_size = HY_SIZE_FOR_STACK_DEPTH(_depth);
    unsigned char *stack_ptr = (unsigned char*)malloc(stack_mem_size);
    if (stack_ptr) {
        unsigned char*cur_ptr = stack_ptr;
        //printf("befor encode\n");
        for (int i = HY_THREAD_STACK_FILTER_DEPTH; i < depth; ++i) {
            //printf("0x%016lx\n", thread_stack[i]);
            memcpy((void*)cur_ptr, (void*)&thread_stack[i], HY_SIZE_PER_STACK);
            cur_ptr += HY_SIZE_PER_STACK;
        }
        _stack = stack_ptr;
    }
    _tid = pthread_mach_thread_np(pthread_self());
}

string DDThreadStack::currentStackInfo()
{
#define TMP_BUF_LEN 32
    char tmp_buf[TMP_BUF_LEN] = {0};
    string stack_info = "{\ntid:";
    sprintf(tmp_buf, "%d", _tid);
    stack_info += tmp_buf;
    stack_info += "\nstack:[";
    unsigned char* cur_stack_ptr = _stack;
    if (cur_stack_ptr) {
        //printf("after decode\n");
        for (int i = 0; i < _depth; ++i) {
            memset(tmp_buf, '\0', TMP_BUF_LEN);
            vm_address_t address = 0;
            memcpy(&address, cur_stack_ptr, HY_SIZE_PER_STACK);
             //printf("0x%016lx\n", address);
            sprintf(tmp_buf, "0x%016lx,", address);
            stack_info += tmp_buf;
            cur_stack_ptr += HY_SIZE_PER_STACK;
        }
    }
    stack_info += "]\n}";
    return stack_info;
}

size_t DDThreadStack::occupyMemorySize()
{
    return HY_SIZE_FOR_STACK_DEPTH(_depth) + sizeof(DDThreadStack);
}



