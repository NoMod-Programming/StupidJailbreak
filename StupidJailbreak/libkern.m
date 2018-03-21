/*
 * libkern.m - Kernel memory related functions.
 *
 * Copyright (c) 2014 Samuel Groß
 * Adapted for StupidJailbreak by Edward Pedemonte
 */

#include <stdlib.h>

#include <mach/mach_types.h>
#include <mach/mach_init.h>
#include <mach/host_priv.h>
#include <mach/vm_map.h>

#include "libkern.h"

#define MAX_CHUNK_SIZE 0x500

vm_size_t read_kernel(task_t _kernel_task, vm_address_t addr, vm_size_t size, unsigned char* buf)
{
    kern_return_t ret;
    vm_size_t remainder = size;
    vm_size_t bytes_read = 0;
    
    vm_address_t end = addr + size;
    
    // reading memory in big chunks seems to cause problems, so
    // we are splitting it up into multiple smaller chunks here
    while (addr < end) {
        size = remainder > MAX_CHUNK_SIZE ? MAX_CHUNK_SIZE : remainder;
        
        ret = vm_read_overwrite(_kernel_task, addr, size, (vm_address_t)(buf + bytes_read), &size);
        if (ret != KERN_SUCCESS || size == 0)
            break;
        
        bytes_read += size;
        addr += size;
        remainder -= size;
    }
    
    return bytes_read;
}

vm_size_t write_kernel(task_t _kernel_task, vm_address_t addr, unsigned char* data, vm_size_t size)
{
    kern_return_t ret;
    vm_size_t remainder = size;
    vm_size_t bytes_written = 0;
    
    vm_address_t end = addr + size;
    
    while (addr < end) {
        size = remainder > MAX_CHUNK_SIZE ? MAX_CHUNK_SIZE : remainder;
        
        ret = vm_write(_kernel_task, addr, (vm_offset_t)(data + bytes_written), size);
        if (ret != KERN_SUCCESS)
            break;
        
        bytes_written += size;
        addr += size;
        remainder -= size;
    }
    
    return bytes_written;
}

vm_address_t find_bytes(task_t _kernel_task, vm_address_t start, vm_address_t end, unsigned char* bytes, size_t length)
{
    vm_address_t ret = 0;
    unsigned char* buf = malloc(end - start);
    if (buf) {
        // TODO reading in chunks would probably be better
        if (read_kernel(_kernel_task, start, end - start, buf)) {
            void* addr = memmem(buf, end - start, bytes, length);
            if (addr)
                ret = (vm_address_t)addr - (vm_address_t)buf + start;
        }
        free(buf);
    }
    
    return ret;
}
