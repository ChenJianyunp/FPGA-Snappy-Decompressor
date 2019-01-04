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

typedef struct
{
    void *dest;
	void *src;
	size_t rd_size;
	size_t wr_size;
	int job_id; 
} job_description;

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
	rc = snap_action_completed((void*)h, NULL, timeout);
	if (rc) rc = 0;   /* Good */
	else rc = ETIME;  /* Timeout */
	if (0 != rc)
		VERBOSE0("%s Timeout Error\n", __func__);
	td = get_usec() - t_start;
	*elapsed = td;
	return rc;
}

/*send all the data in the job descriptions
*/
static void action_decompress(struct snap_card* h,
		job_description jd)
{
	uint64_t addr;

	VERBOSE1(" memcpy(%p, %p, 0x%8.8lx,0x%8.8lx) ", jd.dest, jd.src, jd.rd_size, jd.wr_size);
	addr = (uint64_t)jd.dest;
	action_write(h, ACTION_DEST_LOW, (uint32_t)(addr & 0xffffffff));
	action_write(h, ACTION_DEST_HIGH, (uint32_t)(addr >> 32));
	addr = (uint64_t)jd.src;
	action_write(h, ACTION_SRC_LOW, (uint32_t)(addr & 0xffffffff));
	action_write(h, ACTION_SRC_HIGH, (uint32_t)(addr >> 32));
	action_write(h, ACTION_RD_SIZE, jd.rd_size);
	action_write(h, ACTION_WR_SIZE, jd.wr_size);
	
	action_write(h, ACTION_JOB_ID, jd.job_id | (1<<16));
	action_write(h, ACTION_JOB_ID, 0);
	
	return;
}


/*
send the job discription in the jd_array to the card
*/
static int do_decompression(struct snap_card *h,
			snap_action_flag_t flags,
			int timeout,
			job_description *jd_array, //array to store the jobs
			int num_job //number of jobs in the jd_array
			)

{
	int rc;
	struct snap_action *act = NULL;
	uint64_t td;

	act = snap_attach_action(h, ACTION_TYPE_EXAMPLE,
				  flags, 5 * timeout);
	if (NULL == act) {
		VERBOSE0("Error: Can not attach Action: %x\n", ACTION_TYPE_EXAMPLE);
		VERBOSE0("       Try to run snap_main tool\n");
		return 0x100;
	}
	
	//send all the job descriptions to the card 
	int i;
	for(i = 0; i < num_job ; i++)
		action_decompress(h, jd_array[i]);
	
	rc = action_wait_idle(h, timeout, &td);
//	print_time(td, memsize);
	if (0 != snap_detach_action(act)) {
		VERBOSE0("Error: Can not detach Action: %x\n", ACTION_TYPE_EXAMPLE);
		rc |= 0x100;
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

static job_description generate_job(const char *file, int job_id){
		int rc;
	void *src = NULL;
	void *dest = NULL;
	job_description jd;
	
	/*prepare read data and write space*/
	
	uint8_t *ibuff = NULL, *obuff = NULL;
	ssize_t input_size = 0;
	size_t output_size = 1*64*1024;
	input_size = __file_size(file);
	printf("size of the input is %d \n",(int)input_size);
	ibuff = snap_malloc(input_size);
	if (ibuff == NULL){
		printf("ibuff null");
		return jd;
	}
	
	rc = __file_read(file, ibuff, input_size);
	output_size=get_decompression_length(ibuff); ///calculate the length of the output
	printf("length is %d \n",(int)output_size);
	
/*At the end of decompression, there maybe some garbage with the size of less than 64 bytes.
inorder to save the hardware resource, the garbage will also be transfered back, so in the 
software side, always allocate a more memory for writing back. */
	obuff = snap_malloc(output_size+128);
	if (obuff == NULL){
		printf("obuff null");
		return jd;
	}
	memset(obuff, 0x0, output_size+128);
	
	if (rc < 0){
		printf("rc null");
		return jd;
	}
	src = (void *)ibuff;
	dest = (void *)obuff;
	
	jd.dest = dest;
	jd.src = src;
	jd.rd_size = input_size;
	jd.wr_size = output_size;
	jd.job_id = job_id & 0xFFFF; 
	
	return jd;
}

static void free_job(job_description jd){
	free_mem(jd.dest);
	free_mem(jd.src);	
}

static int decompression_test(struct snap_card* dnc,
			snap_action_flag_t attach_flags,
			int timeout/* Timeout to wait in sec */
			)    
{
	int rc;

	job_description jd[3];

	jd[0] = generate_job("/home/jianyuchen/bulk/snap18/testdata/alice29.txt.snp", 0);
	jd[1] = generate_job("/home/jianyuchen/bulk/snap18/testdata/alice29.txt.snp", 1);
	jd[2] = generate_job("/home/jianyuchen/bulk/snap18/testdata/alice29.txt.snp", 2);
	
	rc = do_decompression(dnc, attach_flags, timeout, jd, 1);
	if (0 == rc) {
		printf("decompression finished");
	}
	/******output the decompression result******/
	FILE * pFile0;
	pFile0=fopen("/home/jianyuchen/bulk/snap18/testdata/test0.txt","wb");
	fwrite((void*)jd[0].dest,sizeof(char),jd[0].wr_size,pFile0);
	printf("output address of job0: %lx \n", (long)(jd[0].dest));
	
	FILE * pFile1;
	pFile1=fopen("/home/jianyuchen/bulk/snap18/testdata/test1.txt","wb");
	fwrite((void*)jd[1].dest,sizeof(char),jd[1].wr_size,pFile1);
	printf("output address of job1: %lx \n", (long)(jd[1].dest));
	
	FILE * pFile2;
	pFile2=fopen("/home/jianyuchen/bulk/snap18/testdata/test2.txt","wb");
	fwrite((void*)jd[2].dest,sizeof(char),jd[2].wr_size,pFile2);
	printf("output address of job2: %lx \n", (long)(jd[2].dest));
	
	free_job(jd[0]);
	free_job(jd[1]);
	free_job(jd[2]);
	
	return 0;
}



static void usage(const char *prog)
{
	VERBOSE0("SNAP Basic Test and Debug Tool.\n"
		"    Use Option -a 1 for SNAP Timer Test's\n"
		"    e.g. %s -a1 -s 1000 -e 2000 -i 200 -v\n"
		"    Use Option -a 2,3,4,5,6 for SNAP DMA Test's\n"
		"    e.g. %s -a2 [-vv] [-I]\n",
		prog, prog);
	VERBOSE0("Usage: %s\n"
		"    -h, --help           print usage information\n"
		"    -v, --verbose        verbose mode\n"
		"    -C, --card <cardno>  use this card for operation\n"
		"    -V, --version\n"
		"    -q, --quiet          quiece output\n"
		"    -a, --action         Action to execute (default 1)\n"
		"    -t, --timeout        Timeout after N sec (default 1 sec)\n"
		"    -I, --irq            Enable Action Done Interrupt (default No Interrupts)\n"
		"    ----- Action 1 Settings -------------- (-a) ----\n"
		"    -s, --start          Start delay in msec (default %d)\n"
		"    -e, --end            End delay time in msec (default %d)\n"
		"    -i, --interval       Inrcrement steps in msec (default %d)\n"
		"    ----- Action 2,3,4,5,6 Settings ------ (-a) -----\n"
		"    -S, --size4k         Number of 4KB Blocks for Memcopy (default 1)\n"
		"    -B, --size64         Number of 64 Bytes Blocks for Memcopy (default 0)\n"
		"    -N, --iter           Memcpy Iterations (default 1)\n"
		"    -A, --align          Memcpy alignemend (default 4 KB)\n"
		"    -D, --dest           Memcpy Card RAM base Address (default 0)\n"
		"\tTool to check Stage 1 FPGA or Stage 2 FPGA Mode (-a) for snap bringup.\n"
		"\t-a 1: Count down mode (Stage 1)\n"
		"\t-a 2: Copy from Host Memory to Host Memory.\n"
		"\t-a 3: Copy from Host Memory to DDR Memory (FPGA Card).\n"
		"\t-a 4: Copy from DDR Memory (FPGA Card) to Host Memory.\n"
		"\t-a 5: Copy from DDR Memory to DDR Memory (both on FPGA Card).\n"
		"\t-a 6: Copy from Host -> DDR -> Host.\n"
		, prog, START_DELAY, END_DELAY, STEP_DELAY);
}


int main(int argc, char *argv[])
{
	char device[128];
	struct snap_card *dn;	/* lib snap handle */
	int start_delay = START_DELAY;
	int end_delay = END_DELAY;
//	int step_delay = STEP_DELAY;
//	int delay;
	int card_no = 0;
	int cmd;
//	int num_4k = 1;	/* Default is 1 4 K Blocks */
	int num_64 = 0;	/* Default is 0 64 Bytes Blocks */
	int rc = 1;
//	int memcpy_iter = DEFAULT_MEMCPY_ITER;
	int memcpy_align = DEFAULT_MEMCPY_BLOCK;
	uint64_t cir;
	int timeout = ACTION_WAIT_TIME;
	snap_action_flag_t attach_flags = 0;
//	uint64_t td;
//	struct snap_action *act = NULL;
	unsigned long ioctl_data;
	unsigned long dma_align;
	unsigned long dma_min_size;
	char card_name[16];   /* Space for Card name */
	
	
	/*****************************/
	
	while (1) {
                int option_index = 0;
		static struct option long_options[] = {
			{ "card",     required_argument, NULL, 'C' },
			{ "verbose",  no_argument,       NULL, 'v' },
			{ "help",     no_argument,       NULL, 'h' },
			{ "version",  no_argument,       NULL, 'V' },
			{ "quiet",    no_argument,       NULL, 'q' },
			{ "start",    required_argument, NULL, 's' },
			{ "end",      required_argument, NULL, 'e' },
			{ "interval", required_argument, NULL, 'i' },
			{ "size4k",   required_argument, NULL, 'S' },
			{ "size64",   required_argument, NULL, 'B' },
			{ "iter",     required_argument, NULL, 'N' },
			{ "align",    required_argument, NULL, 'A' },
			{ "dest",     required_argument, NULL, 'D' },
			{ "timeout",  required_argument, NULL, 't' },
			{ "irq",      no_argument,       NULL, 'I' },
			{ 0,          no_argument,       NULL, 0   },
		};
		cmd = getopt_long(argc, argv, "C:s:e:i:a:S:B:N:A:D:t:IqvVh",
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
		/* Action 1 Options */
		case 's':
			start_delay = strtol(optarg, (char **)NULL, 0);
			break;
		case 'e':
			end_delay = strtol(optarg, (char **)NULL, 0);
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
		case 't':
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

	//do decompression
	rc=decompression_test(dn,attach_flags,timeout);

__exit1:
	// Unmap AFU MMIO registers, if previously mapped
	VERBOSE2("Free Card Handle: %p\n", dn);
	snap_card_free(dn);

	VERBOSE1("End of Test rc: %d\n", rc);
	return rc;
}
