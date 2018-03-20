/*
 * main.m - Helper file
 *
 * Copyright (c) 2017 Siguza & tihmstar
 */

#import <UIKit/UIKit.h>
#import "AppDelegate.h"
#include <dlfcn.h>
int (*dsystem)(const char *) = 0;

int main(int argc, char * argv[]) {
    dsystem = dlsym(RTLD_DEFAULT,"system");
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
