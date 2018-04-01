/*
 * kdump.m - Kernel dumper code
 *
 * Copyright (c) 2014 Samuel Groß
 * Adapted for StupidJailbreak by Edward Pedemonte (NoMod-Programming)
 */

#include "kdump.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <mach/mach_init.h>
#include <mach/mach_types.h>
#include <mach/host_priv.h>
#include <mach/vm_map.h>
#include <mach-o/nlist.h>

#include "libkern.h"
#include "machobinary.h"

#define KERNEL_SIZE 0x1800000
#define HEADER_SIZE 0x1000

#define max(a, b) (a) > (b) ? (a) : (b)

uint64_t machoGetSize(uint8_t firstPage[4096],char *segname,char *sectname);
uint64_t machoGetFileAddr(uint8_t firstPage[4096],char *segname,char *sectname);
uint64_t machoGetVMAddr(uint8_t firstPage[4096],char *segname,char *sectname);

void dump(task_t _kernel_task, vm_address_t _kbase)
{
    // This is spaghetti code, it's this way because of a lot of testing, but I should fix that ASAP
    NSLog(@"Entered dump()...");
    task_t kernel_task = _kernel_task;
    vm_address_t kbase = _kbase;
    unsigned char buf[HEADER_SIZE];      // will hold the original mach-o header and load commands
    unsigned char header[HEADER_SIZE];   // header for the new mach-o file
    unsigned char* binary;               // mach-o will be reconstructed in here
    FILE* f;
    size_t filesize = 0;
    struct segment_command_64* seg;
    struct mach_header_64* orig_hdr = (struct mach_header_64*)buf;
    struct mach_header_64* hdr = (struct mach_header_64*)header;
    NSLog(@"1...");
    
    memset(header, 0, HEADER_SIZE);
    NSLog(@"2...");
    printf("[*] found kernel base at address 0x" ADDR "\n", (unsigned long long) kbase);
    
    // Okay, we're trying something here... Can we just use the header in liboffsetfinder64? Yeah, I think so, considering the header should be all we need...
    
    // Let's open a file properly... Avoid EXC_BAD_ACCESS (it's my first few days using Objective-C)
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docs_dir = [paths objectAtIndex:0];
    NSString* aFile = [docs_dir stringByAppendingPathComponent: @"kernel.bin"];
    f = fopen([aFile fileSystemRepresentation], "wb");
    binary = calloc(1, KERNEL_SIZE);            // too large for the stack
    
    printf("[*] reading kernel header...\n");
    read_kernel(kernel_task, kbase, HEADER_SIZE, buf);
    memcpy(hdr, orig_hdr, sizeof(*hdr));
    NSLog(@"3...");
    //hdr->ncmds = 0;
    //hdr->sizeofcmds = 0;
    //Comment this out because we're going to try to preserve the symbol table if we can
    
    /*
     * We now have the mach-o header with the LC_SEGMENT
     * load commands in it.
     * Next we are going to redo the loading process,
     * parse each load command and read the data from
     * vmaddr into fileoff.
     * Some parts of the mach-o can not be restored (e.g. LC_SYMTAB).
     * The load commands for these parts will be removed from the final
     * executable.
     */
    struct symtab_command* symtab = NULL;
    printf("[*] restoring segments...\n");
    struct load_command * cmd = (struct load_command *) ((orig_hdr) + 1);
    for (uint32_t i = (orig_hdr)->ncmds; i > 0; i--) {
        switch(cmd->cmd) {
            case LC_SEGMENT:
            case LC_SEGMENT_64: {
                seg = (struct segment_command_64*)cmd;
                printf("[+] found segment %s\n", seg->segname);
                read_kernel(kernel_task, seg->vmaddr, seg->filesize, binary + seg->fileoff);
                filesize = max(filesize, seg->fileoff + seg->filesize);
            }
            case LC_UUID:
            case LC_UNIXTHREAD:
            case LC_SOURCE_VERSION:
            case LC_FUNCTION_STARTS:
            case LC_VERSION_MIN_MACOSX:
            case LC_VERSION_MIN_IPHONEOS:
            case LC_VERSION_MIN_TVOS:
            case LC_VERSION_MIN_WATCHOS:
                NSLog(@"Found one of these... Increasing size of ncmds");
                memcpy(header + sizeof(*hdr) + hdr->sizeofcmds, cmd, cmd->cmdsize);
                //hdr->sizeofcmds += cmd->cmdsize;
                //hdr->ncmds++;
                break;
            case LC_SYMTAB:
                NSLog(@"HERE! WE HAVE A SYMTAB. KEEP THAT IN MIND. AND USE IT.");
                symtab = (struct symtab_command*) cmd;
                printf("[+] found symbol table\n");
                read_kernel(kernel_task, kbase + symtab->symoff, symtab->strsize, header + sizeof(*hdr) + symtab->strsize); // Should work... Reads the symbol table from memory and writes it on the header... Gonna print a lot of debugging stuff just in case...
                filesize = max(filesize, symtab->symoff + symtab->strsize);
                NSLog(@"Sigh... 0x%llx 0x%llx 0x%llx 0x%llx", symtab->symoff, symtab->strsize, symtab->nsyms, symtab->stroff);
                break;
            case LC_DYSYMTAB:
                NSLog(@"DYSYMTAB DETECTED. Keep in mind for implementation later\n");
                break;
        }
        cmd = (struct load_command *) ((unsigned long) cmd + cmd->cmdsize);
    }


    // now replace the old header with the new one ...
    memcpy(binary, header, sizeof(*hdr) + orig_hdr->sizeofcmds);
    
    // ... and write the final binary to file
    fwrite(binary, filesize, 1, f);
    
    printf("[*] done, wrote 0x%lx bytes\n", filesize);
    fclose(f);
    free(binary);
    NSLog(@"Done with dump()! Fixing kernel dump now...\n");
    
    
    // New part: FixSegOffset
    /*
     * ########## FixSegOffset ############
     */
    FILE *fp_open = fopen([aFile fileSystemRepresentation],"r");
    if(!fp_open){
        printf("file isn't exist\n");
        exit(1);
    }
    uint8_t firstPage[4096];
    if(fread(firstPage,1,4096,fp_open)!=4096){
        printf("fread error\n");
        exit(1);
    }
    
    fclose(fp_open);
    
    
    struct mach_header *mh = (struct mach_header*)firstPage;
    
    uint32_t cmd_count = mh->ncmds;
    struct load_command *cmds = (struct load_command*)((char*)firstPage+(sizeof(struct mach_header_64)));
    cmd = cmds;
    for (uint32_t i = 0; i < cmd_count; ++i){
        switch (cmd->cmd) {
            case LC_SEGMENT_64:
            {
                printf("\n");
                struct segment_command_64 *seg = (struct segment_command_64*)cmd;
                if (!strcmp(seg->segname,"__TEXT")) {
                    kbase = (uint64_t)seg->vmaddr;
                    if(kbase==0) {
                        NSLog(@"KBase is 0. Should not happen");
                        exit(1);
                    }
                } else {
                    NSLog(@"Get correctly value after cacl: 0x%llx-0x%llx=0x%llx\n",
                           seg->vmaddr,
                           (uint64_t)kbase,
                           (uint64_t)seg->vmaddr-(uint64_t)kbase
                           );
                    seg->fileoff = (uint64_t)seg->vmaddr-(uint64_t)kbase;
                    seg->fileoff = ((seg->fileoff+seg->filesize)>filesize)?filesize-seg->fileoff:seg->fileoff;
                    printf("Start repairing:\n");
                    
                    printf("LC_SEGMENT name:%s\n",seg->segname);
                    printf("|size:0x%x\n",cmd->cmdsize);
                    printf("|vmaddr:0x%llx\n",seg->vmaddr);
                    printf("|vmsize:0x%llx\n",seg->vmsize);
                    printf("|fileoff:0x%llx   (MODIFIED)\n",seg->fileoff);
                    printf("|filesize:0x%x\n",seg->filesize);
                    
                    printf("Then check each sections:\n");
                    
                    const uint32_t sec_count = seg->nsects;
                    struct section_64 *sec = (struct section_64*)((char*)seg + sizeof(struct segment_command_64));
                    
                    for(uint32_t ii = 0; ii <sec_count; ++ii){
                        
                        sec->offset = (uint64_t)sec->addr - (uint64_t)kbase;
                        sec->size = ((sec->offset+sec->size)>filesize)?filesize-sec->offset:sec->size;
                        
                        printf("|---section name: %s\n",sec->sectname);
                        printf("|---section fileoff: 0x%x   (MODIFIED)\n",sec->offset);
                        
                        sec = (struct section_64 *)((char*)sec + sizeof(struct section_64));
                    }
                    printf("|---------------\n");
                }
                
            }
                break;
        }
        cmd = (struct load_command*)((char*)cmd + cmd->cmdsize);
    }
    FILE *aa = fopen([aFile fileSystemRepresentation],"r+");
    if(!aa){
        printf("error when write back 1\n");
        exit(1);
    }
    fwrite(firstPage,1,4096,aa);
    fclose(aa);
    
    // New part: FixFuncSymbol
    printf("\n\n");
    
    fp_open = fopen([aFile fileSystemRepresentation],"r");
    filesize = [[[NSFileManager defaultManager] attributesOfItemAtPath: aFile error: NULL] fileSize];
    if(!fp_open){
        printf("file isn't exist\n");
        exit(1);
    }
    printf("file size is 0x%llx\n\n", filesize);
    void *file_buf = malloc(filesize);
    if(fread(file_buf,1,filesize,fp_open)!=filesize){
        printf("fread error\n");
        exit(1);
    }
    
    fclose(fp_open);
    
    
    mh = (struct mach_header*)file_buf;

    
    uint32_t linkedit_fileoff = (uint32_t)machoGetFileAddr(file_buf,"__LINKEDIT",NULL);
    uint32_t linkedit_size = (uint32_t)machoGetSize(file_buf,"__LINKEDIT",NULL);
    uint64_t text_vm = machoGetVMAddr(file_buf,"__TEXT","__text");
    uint32_t text_size = (uint32_t)machoGetSize(file_buf,"__TEXT","__text");
    
    if(linkedit_fileoff==-1||linkedit_size==-1||text_vm==-1){
        printf("macho Function Error\n");
        exit(1);
    }
    
    uint32_t symoff = 0;
    uint32_t nsyms = 0;
    uint32_t stroff = 0;
    uint32_t strsize = 0;
    
    cmd_count = mh->ncmds;
    cmds = (struct load_command*)((char*)file_buf+(sizeof(struct mach_header_64)));
    cmd = cmds;
    for (uint32_t i = 0; i < cmd_count; ++i){
        switch (cmd->cmd) {
            case LC_SYMTAB:{
                struct symtab_command *sym_cmd = (struct symtab_command*)cmd;
                nsyms = sym_cmd->nsyms;
                strsize = sym_cmd->strsize;
            }
                break;
        }
        cmd = (struct load_command*)((char*)cmd + cmd->cmdsize);
    }
    
    printf("Symbol table %d entries,String table %d bytes\n\n",nsyms,strsize);
    

    struct nlist_64 *nn;
    for(int i = 0;i<linkedit_size;i++){
        nn = file_buf+linkedit_fileoff+i;
        if(nn->n_un.n_strx<strsize&&nn->n_type==0xf&&nn->n_sect==0x1&&nn->n_value>=text_vm&&nn->n_value<text_vm+text_size){
            // 3 Conditions need to be met to find the symbol table
            //   1.) nn->n_type == 0xf
            //   2.) nn->n_sect == 0x1
            //   3.) nn->n_value is in the range of __TEXT__.__text
            symoff = linkedit_fileoff+i;
            stroff = symoff + nsyms*sizeof(struct nlist_64);
            printf("Locate Symbol table in fileoff 0x%x\nand String table in fileoff 0x%x\n\n",symoff,stroff);
            break;
        }
    }
    
    if(symoff==0||stroff==0){
        printf("Can't locate sym/str table\n");
        exit(1);
    }
    
    cmd_count = mh->ncmds;
    cmds = (struct load_command*)((char*)file_buf+(sizeof(struct mach_header_64)));
    cmd = cmds;
    for (uint32_t i = 0; i < cmd_count; ++i){
        switch (cmd->cmd) {
            case LC_SYMTAB:{
                struct symtab_command *sym_cmd = (struct symtab_command*)cmd;
                (*sym_cmd).symoff = symoff;
                (*sym_cmd).stroff = stroff;
            }
                break;
        }
        cmd = (struct load_command*)((char*)cmd + cmd->cmdsize);
    }
    
    aa = fopen([aFile fileSystemRepresentation],"r+");
    if(!aa){
        printf("ptr error when write back 2\n");
        exit(1);
    }
    fwrite(file_buf,1,4096,aa);
    free(file_buf);
    printf("restore symbol/str table Done!\n");
}

uint64_t machoGetVMAddr(uint8_t firstPage[4096],char *segname,char *sectname){
    if(!segname){
        printf("machoH missing segname,it must need segname\n");
        exit(1);
    }
    
    struct mach_header *mh = (struct mach_header*)firstPage;
    
    const uint32_t cmd_count = mh->ncmds;
    struct load_command *cmds = (struct load_command*)((char*)firstPage+(sizeof(struct mach_header_64)));
    struct load_command* cmd = cmds;
    for (uint32_t i = 0; i < cmd_count; ++i){
        switch (cmd->cmd) {
            case LC_SEGMENT_64:
            {
                struct segment_command_64 *seg = (struct segment_command_64*)cmd;
                if(memcmp(seg->segname,segname,strlen(seg->segname))==0){
                    if(!sectname){
                        return seg->vmaddr;
                    }
                    
                    const uint32_t sec_count = seg->nsects;
                    struct section_64 *sec = (struct section_64*)((char*)seg + sizeof(struct segment_command_64));
                    for(uint32_t ii = 0; ii <sec_count; ++ii){
                        if(memcmp(sec->sectname,sectname,strlen(sec->sectname))==0){
                            return sec->addr;
                        }
                        sec = (struct section_64*)((char*)sec + sizeof(struct section_64));
                    }
                    
                }
                
            }
            case LC_SEGMENT:
            {
                struct segment_command *seg = (struct segment_command*)cmd;
                if(memcmp(seg->segname,segname,strlen(seg->segname))==0){
                    if(!sectname){
                        return seg->vmaddr;
                    }
                    
                    
                    const uint32_t sec_count = seg->nsects;
                    struct section *sec = (struct section*)((char*)seg + sizeof(struct segment_command));
                    for(uint32_t ii = 0; ii <sec_count; ++ii){
                        if(memcmp(sec->sectname,sectname,strlen(sec->sectname))==0){
                            return sec->addr;
                        }
                        sec = (struct section*)((char*)sec + sizeof(struct section));
                    }
                    
                }
                
            }
                break;
        }
        cmd = (struct load_command*)((char*)cmd + cmd->cmdsize);
    }
    return -1;
}

uint64_t machoGetFileAddr(uint8_t firstPage[4096],char *segname,char *sectname) {
    if(!segname){
        printf("machoH missing segname,it must need segname\n");
        exit(1);
    }
    
    struct mach_header *mh = (struct mach_header*)firstPage;
    
    int is32 = 1;
    
    if(mh->magic==MH_MAGIC||mh->magic==MH_CIGAM){
        is32 = 1;
    }
    else if(mh->magic==MH_MAGIC_64||mh->magic==MH_CIGAM_64){
        is32 = 0;
    }
    
    const uint32_t cmd_count = mh->ncmds;
    struct load_command *cmds = (struct load_command*)((char*)firstPage+(is32?sizeof(struct mach_header):sizeof(struct mach_header_64)));
    struct load_command* cmd = cmds;
    for (uint32_t i = 0; i < cmd_count; ++i){
        switch (cmd->cmd) {
            case LC_SEGMENT_64:
            {
                struct segment_command_64 *seg = (struct segment_command_64*)cmd;
                if(memcmp(seg->segname,segname,strlen(seg->segname))==0){
                    if(!sectname){
                        return seg->fileoff;
                    }
                    
                    const uint32_t sec_count = seg->nsects;
                    struct section_64 *sec = (struct section_64*)((char*)seg + sizeof(struct segment_command_64));
                    for(uint32_t ii = 0; ii <sec_count; ++ii){
                        if(memcmp(sec->sectname,sectname,strlen(sec->sectname))==0){
                            return sec->offset;
                        }
                        sec = (struct section_64*)((char*)sec + sizeof(struct section_64));
                    }
                    
                }
                
            }
            case LC_SEGMENT:
            {
                struct segment_command *seg = (struct segment_command*)cmd;
                if(memcmp(seg->segname,segname,strlen(seg->segname))==0){
                    if(!sectname){
                        return seg->fileoff;
                    }
                    
                    const uint32_t sec_count = seg->nsects;
                    struct section *sec = (struct section*)((char*)seg + sizeof(struct segment_command));
                    for(uint32_t ii = 0; ii <sec_count; ++ii){
                        if(memcmp(sec->sectname,sectname,strlen(sec->sectname))==0){
                            return sec->offset;
                        }
                        sec = (struct section*)((char*)sec + sizeof(struct section));
                    }
                    
                }
                
            }
                break;
        }
        cmd = (struct load_command*)((char*)cmd + cmd->cmdsize);
    }
    return -1;
}

uint64_t machoGetSize(uint8_t firstPage[4096],char *segname,char *sectname){
    if(!segname){
        printf("machoH missing segname,it must need segname\n");
        exit(1);
    }
    
    struct mach_header *mh = (struct mach_header*)firstPage;
    
    int is32 = 1;
    
    if(mh->magic==MH_MAGIC||mh->magic==MH_CIGAM){
        is32 = 1;
    }
    else if(mh->magic==MH_MAGIC_64||mh->magic==MH_CIGAM_64){
        is32 = 0;
    }
    
    const uint32_t cmd_count = mh->ncmds;
    struct load_command *cmds = (struct load_command*)((char*)firstPage+(is32?sizeof(struct mach_header):sizeof(struct mach_header_64)));
    struct load_command* cmd = cmds;
    for (uint32_t i = 0; i < cmd_count; ++i){
        switch (cmd->cmd) {
            case LC_SEGMENT_64:
            {
                struct segment_command_64 *seg = (struct segment_command_64*)cmd;
                if(memcmp(seg->segname,segname,strlen(seg->segname))==0){
                    if(!sectname){
                        return seg->filesize;
                    }
                    
                    const uint32_t sec_count = seg->nsects;
                    struct section_64 *sec = (struct section_64*)((char*)seg + sizeof(struct segment_command_64));
                    for(uint32_t ii = 0; ii <sec_count; ++ii){
                        if(memcmp(sec->sectname,sectname,strlen(sec->sectname))==0){
                            return sec->size;
                        }
                        sec = (struct section_64*)((char*)sec + sizeof(struct section_64));
                    }
                    
                }
                
            }
            case LC_SEGMENT:
            {
                struct segment_command *seg = (struct segment_command*)cmd;
                if(memcmp(seg->segname,segname,strlen(seg->segname))==0){
                    if(!sectname){
                        return seg->filesize;
                    }
                    
                    const uint32_t sec_count = seg->nsects;
                    struct section *sec = (struct section*)((char*)seg + sizeof(struct segment_command));
                    for(uint32_t ii = 0; ii <sec_count; ++ii){
                        if(memcmp(sec->sectname,sectname,strlen(sec->sectname))==0){
                            return sec->size;
                        }
                        sec = (struct section*)((char*)sec + sizeof(struct section));
                    }
                    
                }
                
            }
                break;
        }
        cmd = (struct load_command*)((char*)cmd + cmd->cmdsize);
    }
    return -1;
}
