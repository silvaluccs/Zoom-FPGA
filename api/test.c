#include <stdio.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>

#define LW_BRIDGE_BASE 0xFF200000
#define LW_BRIDGE_SPAM 0x00005000

int main(void)
{
    volatile int *IP_ptr; // virtual address pointer to red LEDs]
    volatile int *EN_ptr;
    int fd = -1; // used to open /dev/mem
    void *LW_virtual; // physical addresses for light-weight bridge

    // Open /dev/mem to give access to physical addresses
    if ((fd = open("/dev/mem", (O_RDWR | O_SYNC))) == -1) {
        printf("ERROR: could not open /dev/mem ...\n");
        return (-1);
    }

    // Get a mapping from physical addresses to virtual addresses
    LW_virtual = mmap(NULL, LW_BRIDGE_SPAM, (PROT_READ | PROT_WRITE), MAP_SHARED, fd, LW_BRIDGE_BASE);
    if (LW_virtual == MAP_FAILED) {
        printf("ERROR: mmap() failed ...\n");
        close(fd);
        return (-1);
    }

    // Set virtual address pointer to I/O port
    IP_ptr = (int *)(LW_virtual + 0x0);
    EN_ptr = (int *)(LW_virtual + 0x10);

    *IP_ptr = 0xC0000000;

        sleep(10); // Pause for 3 seconds
    *EN_ptr = 0x00000001;
 sleep(10); 
    *EN_ptr = 0x00000000;
 sleep(10); 

    // Close the previously-opened virtual address mapping
    if (munmap(LW_virtual, LW_BRIDGE_SPAM) != 0) {
        printf("ERROR: munmap() failed ...\n");
        return (-1);
    }

    // Close /dev/mem to give access to physical addresses
    close(fd);

    return 0;
}

