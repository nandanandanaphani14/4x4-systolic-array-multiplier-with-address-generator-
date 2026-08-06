/*=====================================================================
 * accel_monitor.c  --  bare-metal UART text console for the 4x4 systolic
 * accelerator, driven through the accel_axi AXI4-Lite wrapper.
 *
 * Target : Zynq-7000 PS on the ZedBoard, output over the on-board
 *          USB-UART (PS UART1, MIO48/49).  Build in Vitis as a bare-metal
 *          application on a hello-world-style BSP.
 *
 * It offers a tiny menu on the serial terminal (115200-8-N-1):
 *   d  run the built-in 4x4 x 4x4 demo (identity-style W/A)
 *   w  enter the 16 weight bytes (row-major W[r][c])
 *   a  enter the 16 activation bytes (row-major A[i][r])
 *   r  run the job (num_vectors = 4)
 *   p  print the 4x4 result matrix
 *   ?  help
 *
 * The accelerator RTL and the AXI wrapper are unchanged; this is pure
 * software.  Replace ACCEL_BASE with the value Vivado assigns (see
 * xparameters.h -> XPAR_ACCEL_AXI_0_S_AXI_BASEADDR).
 *===================================================================*/
#include <stdio.h>
#include "xil_io.h"
#include "xparameters.h"

/* Base address of the accel_axi slave (from xparameters.h). */
#ifdef XPAR_ACCEL_AXI_0_S_AXI_BASEADDR
  #define ACCEL_BASE  XPAR_ACCEL_AXI_0_S_AXI_BASEADDR
#else
  #define ACCEL_BASE  0x43C00000u   /* typical default; confirm in xparameters.h */
#endif

/* register indices (byte offset = idx*4), see accel_axi.sv */
#define R_NUMVEC   0
#define R_ACTBASE  1
#define R_OUTBASE  2
#define R_WDATA    3
#define R_WCOMMIT  4
#define R_ADATA    5
#define R_ACOMMIT  6
#define R_START    7
#define R_OADDR    8
#define R_STATUS   9
#define R_ORD0     10

#define WR(idx,val)  Xil_Out32(ACCEL_BASE + ((idx)*4), (u32)(val))
#define RD(idx)      Xil_In32 (ACCEL_BASE + ((idx)*4))

#define STATUS_BUSY  0x1
#define STATUS_DONE  0x2

static signed char W[4][4];   /* weight matrix   W[r][c] */
static signed char A[4][4];   /* activation rows A[i][r] */

/* pack four signed int8 lanes into one 32-bit word, lane0 = low byte */
static u32 pack(signed char l0, signed char l1, signed char l2, signed char l3){
    return ((u32)(u8)l0)       | (((u32)(u8)l1) << 8)
         | (((u32)(u8)l2) << 16) | (((u32)(u8)l3) << 24);
}

static void load_weights(void){
    for (int r = 0; r < 4; r++){
        WR(R_WDATA,  pack(W[r][0], W[r][1], W[r][2], W[r][3]));
        WR(R_WCOMMIT, r);                 /* commits weight_mem[r] */
    }
}
static void load_activations(void){
    for (int i = 0; i < 4; i++){
        WR(R_ADATA,  pack(A[i][0], A[i][1], A[i][2], A[i][3]));
        WR(R_ACOMMIT, i);                 /* commits a_mem[i] */
    }
}

static void run_job(void){
    load_weights();
    load_activations();
    WR(R_NUMVEC,  4);
    WR(R_ACTBASE, 0);
    WR(R_OUTBASE, 0);
    WR(R_START,   1);                     /* pulse start (clears sticky done) */
    /* poll the sticky done bit */
    u32 guard = 0;
    while (!(RD(R_STATUS) & STATUS_DONE)) {
        if (++guard > 1000000u) { printf("  [timeout waiting for done]\r\n"); return; }
    }
}

static void print_result(void){
    printf("  C = A x W :\r\n");
    for (int row = 0; row < 4; row++){
        WR(R_OADDR, row);                 /* select output_mem[row] */
        (void)RD(R_STATUS);               /* small delay: let read latency settle */
        (void)RD(R_STATUS);
        int c0 = (int)RD(R_ORD0 + 0);
        int c1 = (int)RD(R_ORD0 + 1);
        int c2 = (int)RD(R_ORD0 + 2);
        int c3 = (int)RD(R_ORD0 + 3);
        printf("    [ %6d %6d %6d %6d ]\r\n", c0, c1, c2, c3);
    }
}

static int read_int(void){               /* read a signed integer from the terminal */
    int v = 0, s = 1, c, got = 0;
    do { c = getchar(); } while (c==' '||c=='\r'||c=='\n'||c=='\t');
    if (c=='-'){ s=-1; c=getchar(); }
    while (c>='0' && c<='9'){ v = v*10 + (c-'0'); got=1; c=getchar(); }
    return got ? s*v : 0;
}

static void enter_matrix(signed char m[4][4], const char *name, const char *idx){
    printf("  enter 16 values for %s, row-major %s (signed -128..127):\r\n", name, idx);
    for (int r = 0; r < 4; r++)
        for (int c = 0; c < 4; c++)
            m[r][c] = (signed char)read_int();
    printf("  captured.\r\n");
}

static void load_demo(void){             /* identity-style 4x4 x 4x4 */
    signed char Wd[4][4] = {{1,2,3,4},{5,6,7,8},{9,10,11,12},{13,14,15,16}};
    signed char Ad[4][4] = {{1,0,0,0},{0,1,0,0},{0,0,1,0},{1,1,1,1}};
    for (int r=0;r<4;r++) for(int c=0;c<4;c++){ W[r][c]=Wd[r][c]; A[r][c]=Ad[r][c]; }
    printf("  demo matrices loaded (expect result row 3 = 28 32 36 40).\r\n");
}

static void help(void){
    printf("\r\n 4x4 systolic accelerator monitor\r\n"
           "   d  load built-in demo matrices\r\n"
           "   w  enter weight matrix W[r][c]\r\n"
           "   a  enter activation matrix A[i][r]\r\n"
           "   r  run the job\r\n"
           "   p  print the result matrix\r\n"
           "   ?  this help\r\n");
}

int main(void){
    help();
    for (;;){
        printf("\r\naccel> ");
        int c = getchar();
        switch (c){
            case 'd': load_demo();        break;
            case 'w': enter_matrix(W, "weights",     "W[r][c]"); break;
            case 'a': enter_matrix(A, "activations", "A[i][r]"); break;
            case 'r': printf("  running...\r\n"); run_job(); printf("  done.\r\n"); break;
            case 'p': print_result();     break;
            case '?': help();             break;
            case '\r': case '\n': case ' ': break;
            default: printf("  unknown '%c' - press ? for help\r\n", c); break;
        }
    }
    return 0;
}
