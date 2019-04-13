/********************************************
Name: 		snap_decompressor
Author: 	Jianyu Chen
School: 	Delft Univsersity of Technology
Date:		12th July, 2018
Function:	This a program to test the hardware Snappy decompressor, 
			it will read compressed data from a file, send the command
			to the FPGA (or FPGA simulation). After the decompression,
			it will output the decompression result to a file.
********************************************/

#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>
#include <errno.h>
#include <malloc.h>
#include <unistd.h>
#include <sys/time.h>
#include <getopt.h>
#include <ctype.h>

#include <libsnap.h>
#include <snap_tools.h>
#include <snap_s_regs.h>

#include "snap_example.h"

/*	defaults */
#define	START_DELAY		200
#define	END_DELAY		2000
#define	STEP_DELAY		200
#define	DEFAULT_MEMCPY_BLOCK	4096
#define	DEFAULT_MEMCPY_ITER	1
#define ACTION_WAIT_TIME	1	/* Default in sec */

#define	MEGAB		(1024*1024ull)
#define	GIGAB		(1024 * MEGAB)


#define VERBOSE0(fmt, ...) do {			\
		printf(fmt, ## __VA_ARGS__);    \
} while (0)

#define VERBOSE1(fmt, ...) do {			\
	if (verbose_level > 0)			\
		printf(fmt, ## __VA_ARGS__);    \
} while (0)

#define VERBOSE2(fmt, ...) do {			\
	if (verbose_level > 1)			\
		printf(fmt, ## __VA_ARGS__);    \
} while (0)


#define VERBOSE3(fmt, ...) do {			\
	if (verbose_level > 2)			\
		printf(fmt, ## __VA_ARGS__);    \
} while (0)

#define VERBOSE4(fmt, ...) do {			\
	if (verbose_level > 3)			\
		printf(fmt, ## __VA_ARGS__);	\
} while (0)

static const char *version = GIT_VERSION;
static	int verbose_level = 0;

int get_decompression_length(uint8_t *);

static uint64_t get_usec(void)
{
    struct timeval t;

    gettimeofday(&t, NULL);
    return t.tv_sec * 1000000 + t.tv_usec;
}


static void free_mem(void *a)
{
    VERBOSE2("Free Mem %p\n", a);
    if (a)
        free(a);
}


/* Action or Kernel Write and Read are 32 bit MMIO */
static void action_write(struct snap_card* h, uint32_t addr, uint32_t data)
{
    int rc;

    rc = snap_mmio_write32(h, (uint64_t)addr, data);
    if (0 != rc)
        VERBOSE0("Write MMIO 32 Err\n");
    return;
}


/*
 *  an complete function alternative
 *  same as action_action_completed but more MMIO info feedback
*/
static int snap_action_completed_withMMIO(struct snap_action *action, int *rc, int timeout)
{
    // More MMIO read can be done in this function

	int _rc = 0;
	uint32_t action_data = 0;
	struct snap_card *card = (struct snap_card *)action;
	unsigned long t0;
	int dt, timeout_us;

	uint32_t rc2=0;
	int counter=0;

	/* Busy poll timout sec */
	t0 = get_usec();
	dt = 0;
	timeout_us = timeout * 1000 * 1000;
	while (dt < timeout_us) {
		_rc = snap_mmio_read32(card, ACTION_CONTROL, &action_data);

		if(rc2!=action_data) {
			counter ++;
			printf("State %d -- (Register Code): %d\n",counter,action_data);
			rc2=action_data;
		}

        /*  TODO:
         *  1. add more MMIO read if needed
         *  2. #define
        */

		if ((action_data & ACTION_CONTROL_IDLE) == ACTION_CONTROL_IDLE)
			break;
		dt = (int)(get_usec() - t0);
	}
	if (rc)
		*rc = _rc;

	// Test the rc in calling function for normal or timeout (rc=0) termination
	return (action_data & ACTION_CONTROL_IDLE) == ACTION_CONTROL_IDLE;
}


/*
 *	Start Action and wait for Idle.
 */
static int action_wait_idle(struct snap_card* h, int timeout, uint64_t *elapsed)
{
    int rc = 0;
    uint64_t t_start;   /* time in usec */
    uint64_t td = 0;    /* Diff time in usec */

    /* FIXME Use struct snap_action and not struct snap_card */
    snap_action_start((void*)h);

    /* Wait for Action to go back to Idle */
    t_start = get_usec();
//    rc = snap_action_completed((void*)h, NULL, timeout);
    rc = snap_action_completed_withMMIO((void*)h, NULL, timeout);
    if (rc) rc = 0;   /* Good */
    else rc = ETIME;  /* Timeout */
    if (0 != rc)
        VERBOSE0("%s Timeout Error\n", __func__);
    td = get_usec() - t_start;
    *elapsed = td;
    return rc;
}


static void action_decompress(struct snap_card* h,
        void *dest,
        const void *src,
        size_t rd_size,
        size_t wr_size)
{
    uint64_t addr;

    VERBOSE1(" decompress from %p to %p\n with input size %ld and output size %ld\n", src, dest, rd_size,wr_size);
    addr = (uint64_t)dest;
    action_write(h, ACTION_DEST_LOW, (uint32_t)(addr & 0xffffffff));
    action_write(h, ACTION_DEST_HIGH, (uint32_t)(addr >> 32));
    addr = (uint64_t)src;
    action_write(h, ACTION_SRC_LOW, (uint32_t)(addr & 0xffffffff));
    action_write(h, ACTION_SRC_HIGH, (uint32_t)(addr >> 32));
    action_write(h, ACTION_RD_SIZE, rd_size);
    action_write(h, ACTION_WR_SIZE, wr_size);

    return;
}



static int do_decompression(struct snap_card *h,
            snap_action_flag_t flags,
            int timeout,
            void *dest,
            void *src,
            unsigned long rd_size,
            unsigned long wr_size,
            int skip_Detach
)
{
    int rc;
    struct snap_action *act = NULL;
    uint64_t td;

    /* attach the action */
    act = snap_attach_action(h, ACTION_TYPE_EXAMPLE, flags, 5 * timeout);
    if (NULL == act) {
        VERBOSE0("Error: Can not attach Action: %x\n", ACTION_TYPE_EXAMPLE);
        VERBOSE0("       Try to run snap_main tool\n");
        return 0x100;
    }

    /* send action control data */
    action_decompress(h, dest, src, rd_size,wr_size);

    /* start the action and wait for it ends */
    rc = action_wait_idle(h, timeout, &td);

    if (rc == 0 ) // No timeout
    	printf("Decompression was done in %lf ms\n", (double)(td/1000.));

    if(skip_Detach==0) { /* No '-S' option, so do not skip detach*/
        if (0 != snap_detach_action(act)) {
            VERBOSE0("Error: Can not detach Action: %x\n", ACTION_TYPE_EXAMPLE);
            rc |= 0x100;
        }
    }
    else {
        printf("Warning: Action detach is skipped!\n");
    }
    return rc;
}

/*calculate the length of the uncompressed data
src: the source of the compressed data*/
int get_decompression_length(uint8_t * src){
    int length=0;
    length|=(src[0] & 0x7f);
    if(src[0]&0x80){
        length |= (src[1]&0x7f)<<7;
    }else{
        return length;
    }
    if(src[1]&0x80){
        length |= (src[2]&0x7f)<<14;
    }else{
        return length;
    }
    if(src[2]&0x80){
        length |= (src[3]&0x7f)<<21;
    }else{
        return length;
    }
    if(src[3]&0x80){
        length |= (src[4]&0x7f)<<28;
    }else{
        return length;
    }
        return length;
}


static int decompression_test(struct snap_card* dnc,
            snap_action_flag_t attach_flags,
            int timeout,/* Timeout to wait in sec */
            char* inputfile,
            char* outputfile,
            int skip_Detach
            )    
{
    int rc;
    void *src = NULL;
    void *dest = NULL;

    /*prepare read data and write space*/
    
	uint8_t *ibuff = NULL, *obuff = NULL;
    ssize_t size = 0;
    size_t set_size = 1*64*1024;

    printf("1: The input file is: %s\n",inputfile);
    size = __file_size(inputfile);
    printf("The size of the input is %d \n",(int)size);
    ibuff = snap_malloc(size);
    if (ibuff == NULL){
        printf("ibuff null");
        return 1;
    }

    printf("2: The output file is: %s\n",outputfile);
	
    rc = __file_read(inputfile, ibuff, size);
    set_size=get_decompression_length(ibuff); ///calculate the length of the output
    printf("The size of the output is %d \n",(int)set_size);
	
/*At the end of decompression, there maybe some garbage with the size of less than 64 bytes.
inorder to save the hardware resource, the garbage will also be transfered back, so in the 
software side, always allocate a more memory for writing back. */
    obuff = snap_malloc(set_size+128);
    if (obuff == NULL){
        printf("obuff null");
        return 1;
    }

    /* initial the memory to 'A' for debug */
    memset(obuff, (int)('A'), set_size+128);

    if (rc < 0){
        printf("rc null");
        return 1;
    }
    src = (void *)ibuff;
    dest = (void *)obuff;

    rc = do_decompression(dnc, attach_flags, timeout, dest, src, size, set_size, skip_Detach);
    if (0 == rc) {
        printf("decompression finished - compression factor on this file was %d %% \n", (int)(100. - (100.*size)/set_size));
    }
	/******output the decompression result******/
    FILE * pFile;
    pFile=fopen(outputfile,"wb");
    fwrite((void*)obuff,sizeof(char),set_size,pFile);

    free_mem(ibuff);
    free_mem(obuff);
	
    return 0;
}



static void usage(const char *prog)
{
    VERBOSE0("SNAP Based FPGA Snappy Decompressor.\n"
        "    e.g. %s -v -t 10 -i <input> -o <output>\n", prog);
    VERBOSE0("Usage: %s\n"
        "    -h, --help           print usage information\n"
        "    -v, --verbose        verbose mode\n"
        "    -C, --card <cardno>  use this card for operation\n"
        "    -V, --version\n"
        "    -t, --timeout        Timeout after N sec (default 1 sec)\n"
        "    -s, --start          Start delay in msec (default %d)\n"
        "    -e, --end            End delay time in msec (default %d)\n"
        "    -i, --input          Specify the input file (in simulation, please use abs path)\n"
        "    -o, --ouput          Specify the output file (in simulation, please use abs path)\n"
        "    -S. --skip           Skip detach for debug only (do not use this in release version)\n"

        "    -B, --size64         Number of 64 Bytes Blocks for Memcopy (default 0)\n"
        "    -A, --align          Memcpy alignemend (default 4 KB)\n"
        , prog, START_DELAY, END_DELAY);
}

static void printVersion()
{
	const char date_version[128] = "Decompressor 2019-02-01-v001";
	printf("**************************************************************\n");  // 58 *
	printf("**     App Version: %-*s**\n", 40, date_version);                    // 18 chars, need 40 more
	printf("**************************************************************\n\n");
}


int main(int argc, char *argv[])
{
    char device[128];
    char inputfile[256]="testdata/test.snp";
    char outputfile[256]="testdata/test.txt";
    int skip_Detach = 0;
    struct snap_card *dn;	/* lib snap handle */
    int start_delay = START_DELAY;
    int end_delay = END_DELAY;
    int card_no = 0;
    int cmd;
    int num_64 = 0;	/* Default is 0 64 Bytes Blocks */
    int rc = 1;
    int memcpy_align = DEFAULT_MEMCPY_BLOCK;
    uint64_t cir;
    int timeout = ACTION_WAIT_TIME;
    snap_action_flag_t attach_flags = 0;
    unsigned long ioctl_data;
    unsigned long dma_align;
    unsigned long dma_min_size;
    char card_name[16];   /* Space for Card name */

    /* print the Software Version */
    printVersion();

    /***********************  Argument Parsing  *************************/
    while (1) {
        int option_index = 0;
        static struct option long_options[] = {
            { "card",     required_argument, NULL, 'C' },
            { "verbose",  no_argument,       NULL, 'v' },
            { "help",     no_argument,       NULL, 'h' },
            { "version",  no_argument,       NULL, 'V' },
            { "start",    required_argument, NULL, 's' },
            { "end",      required_argument, NULL, 'e' },
            { "input",    required_argument, NULL, 'i' },
            { "output",   required_argument, NULL, 'o' },
            { "size64",   required_argument, NULL, 'B' },
            { "align",    required_argument, NULL, 'A' },
            { "timeout",  required_argument, NULL, 't' },
            { "irq",      no_argument,       NULL, 'I' },
            { "skip",     no_argument,       NULL, 'S' },
            { 0,          no_argument,       NULL, 0   },
        };
        cmd = getopt_long(argc, argv, "C:s:e:i:o:B:A:t:IvVh",
            long_options, &option_index);
        if (cmd == -1)  /* all params processed ? */
            break;

        switch (cmd) {
        case 'v':	/* verbose */
            verbose_level++;
            break;
        case 'V':	/* version */
            VERBOSE0("%s\n", version);
            exit(EXIT_SUCCESS);;
        case 'h':	/* help */
            usage(argv[0]);
            exit(EXIT_SUCCESS);;
        case 'C':	/* card */
            card_no = strtol(optarg, (char **)NULL, 0);
            break;
        case 's':   /* start delay */
            start_delay = strtol(optarg, (char **)NULL, 0);
            break;
        case 'e':   /* end delay */
            end_delay = strtol(optarg, (char **)NULL, 0);
            break;
        case 'i':   /* input file */
            strcpy(inputfile,optarg);
            break;
        case 'o':   /* output file */
            strcpy(outputfile,optarg);
            break;
        case 'S':   /* skip detach */
            skip_Detach++;
            break;
        case 'B':	/* size64 */
            num_64 = strtol(optarg, (char **)NULL, 0);
            break;
        case 'A':	/* align */
            memcpy_align = strtol(optarg, (char **)NULL, 0);
            if (memcpy_align > DEFAULT_MEMCPY_BLOCK) {
                VERBOSE0("ERROR: Align (-A %d) is to high. Max: %d Bytes\n",
                    memcpy_align, DEFAULT_MEMCPY_BLOCK);
                exit(1);
            }
            break;
        case 't':   /* timeout */
            timeout = strtol(optarg, (char **)NULL, 0); /* in sec */
            break;
        case 'I':      /* irq */
            attach_flags = SNAP_ACTION_DONE_IRQ | SNAP_ATTACH_IRQ;
            break;
        default:
            usage(argv[0]);
            exit(EXIT_FAILURE);
        }
    }

    if (end_delay > 16000) {
        usage(argv[0]);
        exit(1);
    }
    if (start_delay > end_delay) {
        usage(argv[0]);
        exit(1);
    }
    if (card_no > 4) {
        usage(argv[0]);
        exit(1);
    }
    /***********************  End Argument Parsing  *************************/


    sprintf(device, "/dev/cxl/afu%d.0s", card_no);
    VERBOSE2("Open Card: %d device: %s\n", card_no, device);
    dn = snap_card_alloc_dev(device, SNAP_VENDOR_ID_IBM, SNAP_DEVICE_ID_SNAP);
    if (NULL == dn) {
        VERBOSE0("ERROR: Can not Open (%s)\n", device);
        errno = ENODEV;
        perror("ERROR");
        return -1;
    }

    /* Read Card Name */
    snap_card_ioctl(dn, GET_CARD_NAME, (unsigned long)&card_name);
    VERBOSE1("SNAP on %s", card_name);

    snap_card_ioctl(dn, GET_SDRAM_SIZE, (unsigned long)&ioctl_data);
    VERBOSE1(" Card, %d MB of Card Ram avilable. ", (int)ioctl_data);

    snap_card_ioctl(dn, GET_DMA_ALIGN, (unsigned long)&dma_align);
    VERBOSE1(" (Align: %d ", (int)dma_align);

    snap_card_ioctl(dn, GET_DMA_MIN_SIZE, (unsigned long)&dma_min_size);
    VERBOSE1(" Min DMA: %d Bytes)\n", (int)dma_min_size);

    /* Check Align and DMA Min Size */
    if (memcpy_align & (int)(dma_align-1)) {
        VERBOSE0("ERROR: Option -A %d must be a multiple of %d Bytes for %s Cards.\n",
            memcpy_align, (int)dma_align, card_name);
        rc = 0x100;
        goto __exit1;
    }
    if (num_64*64 & (int)(dma_min_size-1)) {
        VERBOSE0("ERROR: Option -B %d must be a multiple of %d Bytes for %s Cards.\n",
            num_64, (int)dma_min_size, card_name);
        rc = 0x100;
        goto __exit1;
    }
    snap_mmio_read64(dn, SNAP_S_CIR, &cir);
  VERBOSE1("Start of Action Card Handle: %p Context: %d\n", dn, (int)(cir & 0x1ff));

    /* start decompression */
    rc=decompression_test(dn, attach_flags, timeout, inputfile, outputfile, skip_Detach);

__exit1:
    // Unmap AFU MMIO registers, if previously mapped
    VERBOSE2("Free Card Handle: %p\n", dn);
    snap_card_free(dn);

    VERBOSE1("End of Test rc: %d\n", rc);
    return rc;
}
