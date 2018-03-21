//
//  kdump.h
//  StupidJailbreak
//

#ifndef kdump_h
#define kdump_h

#include <mach/mach_types.h>

void dump(task_t _kernel_task, vm_address_t _kbase);

#endif /* kdump_h */

