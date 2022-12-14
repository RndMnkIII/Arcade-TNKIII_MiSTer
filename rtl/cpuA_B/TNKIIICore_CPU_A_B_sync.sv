//TNKIIICore_CPU_A_B_sync.sv
//Author: @RndMnkIII
//Date:   25/05/2022
`default_nettype none
`timescale 1ns/100ps

module TNKIIICore_CPU_A_B_sync
(
    input  wire VIDEO_RSTn,
    input  wire clk, //53.6MHz
    input  wire pause_cpu,
    input  wire H0,
	 input  wire CK1,
    input  wire Cen_p,
    input  wire Cen_n,
    input wire clk_13p4b_cen,
    input  wire RESETn,
    input wire [15:0] PLAYER1,
    input wire [15:0] PLAYER2,
	 input wire [15:0] DSW,
    input  wire VBL,
    input  wire BWA,
    input  wire A_B,
    input  wire RLA,
    input  wire RLB,
    input  wire WBA,
    input  wire WBB,
    input  wire VDG,
    output logic VRDn,
    output logic AE, //cpuA Enable
    output logic BE, //cpuB Enable
    //CPU A data bus
    output logic [7:0] CPUAD, //Cpu A data bus  
    output logic CPUA_RD,
    output logic CPUA_WR,

    //common address bus
    output logic [12:0] VA,
    //common data bus
    output logic [7:0] V_out,
    input  wire  [7:0] V_in,

    //hps_io rom interface
	input wire         [24:0] ioctl_addr,
	input wire         [7:0] ioctl_data,
	input wire         ioctl_wr,
    
    //IO devices
    input  wire  SND_BUSY,
    output logic COIN,
    output logic P1,
    output logic P2,
    output logic P1_P2,
    output logic MCODE,
    output logic DIP1,
    output logic DIP2,

    //video devices
    output logic FRONT_VIDEO_CSn,
    output logic SIDE_VRAM_CSn,
    output logic DISC,
    output logic MSB, //Video Attribs.
    output logic FSX, //Front video scroll X
    output logic FSY, //Fraont video scroll Y
    output logic B1SX, //Back1 video scroll X
    output logic B1SY, //Back1 video scroll Y
    output logic COIN_COUNTERS,
    output logic BACK1_VRAM_CSn
);
    logic VD_to_cpuAdbus; //LS32
    logic VD_to_cpuBdbus; //LS32


    //rom download selector
    logic P1_4E_cs, P2_4F_cs, P3_4H_cs;     //16KbytesX3 Main  CPU EPROMs 
    logic P4_2E_cs, P5_2F_cs, P6_2H_cs;     //16KbytesX3 Sub   CPU EPROMs
    selector_cpuAB_rom selector
    (
        .ioctl_addr(ioctl_addr),
        .P1_8D_cs(P1_4E_cs), .P2_7D_cs(P2_4F_cs), .P3_5D_cs(P3_4H_cs),
        .P4_3D_cs(P4_2E_cs), .P5_2D_cs(P5_2F_cs), .P6_1D_cs(P6_2H_cs)
    );

    // ----------------- Z80A Cpu -----------------
    //output
    logic cpuA_nM1;
    logic cpuA_nMR;
    logic cpuA_nIO /* synthesis syn_keep = 1 */;
    logic cpuA_nRD;
    logic cpuA_nWR;
    logic cpuA_nRFSH;
    logic cpuA_nHALT;
    logic cpuA_nBUSACK;
    //input
    logic cpuA_nINT;
    logic cpuA_nNMI;
    logic [15:0] cpuA_A; //AA
    logic [7:0] cpuA_Vin, cpuB_Vin;

    logic E4_1_Qn;
    DFF_pseudoAsyncClrPre2 #(.W(1)) e4_1 (
        .clk(clk),
        .rst(~VIDEO_RSTn),
        .din(1'b1),
        .q(),
        .qn(cpuA_nINT),
        .set(1'b0),    // active high
        .clr(~cpuA_nIO),    // active high
        .cen(VBL) // signal whose edge will trigger the FF
    );

    reg [7:0] cpuA_Din;
    reg [7:0] cpuA_Dout;

    // local reset
    reg reset_n=1'b0;
    reg [5:0] rst_cnt;

    always @(posedge clk)
        if( ~RESETn ) begin
            rst_cnt <= 'd0;
            reset_n <= 1'b0;
        end else begin
            if( rst_cnt != ~6'b0 ) begin
                reset_n <= 1'b0;
                rst_cnt <= rst_cnt + 6'd1;
            end else reset_n <= 1'b1;
        end

    //T80pa CLK x4 real CPU clock
        T80pa z80_E5 (
        //tv80pa z80_E5 (
        .RESET_n(reset_n), //RESETn
        .CLK    (clk),
        .CEN_p  (Cen_p & ~pause_cpu), //active high
        .CEN_n  (Cen_n & ~pause_cpu), //active high
        //.WAIT_n (~pause_cpu),
        .WAIT_n (1'b1),
        .INT_n  (cpuA_nINT),
        .NMI_n  (cpuA_nNMI),
        .RD_n   (cpuA_nRD),
        .WR_n   (cpuA_nWR),
        .A      (cpuA_A),
        .DI     (cpuA_Din),
        .DO     (cpuA_Dout),
        .IORQ_n (cpuA_nIO),
        .M1_n   (cpuA_nM1),
        .MREQ_n (cpuA_nMR),
        .BUSRQ_n(1'b1),
        .BUSAK_n(cpuA_nBUSACK),
        .OUT0   (1'b0),
        .RFSH_n (cpuA_nRFSH),
        .HALT_n (cpuA_nHALT)
    );

    assign CPUA_WR = cpuA_nWR;
    assign CPUA_RD = cpuA_nRD;
    
    //---------------------------------------------

    //------------ CPUA Memory Mapper -------------
     logic C5_1_Y3n;
     logic CS_ROM_P3n;
     logic CS_ROM_P2n;
     logic CS_ROM_P1n;
    //              1 1 1 1  1 | 1     |
    //Address:      5 4 3 2  1 | 0 9 8 | 7 6 5 4  3 2 1 0
    //16'h0000-3FFF 0 0 x x  x | x x x | x x x x  x x x x CS_ROM_P1n R  
    //16'h4000-7FFF 0 1 x x  x | x x x | x x x x  x x x x CS_ROM_P2n R
    //16'h8000-BFFF 1 0 x x  x | x x x | x x x x  x x x x CS_ROM_P3n R 
    ttl_74139_nodly c5_1(.Enable_bar(1'b0), .A_2D(cpuA_A[15:14]), .Y_2D({C5_1_Y3n, CS_ROM_P3n, CS_ROM_P2n, CS_ROM_P1n}));

    logic C7_3_OR; //2-Input OR
    assign C7_3_OR = cpuA_nMR | C5_1_Y3n;  

    //--- AE logic ---
    logic C7_1_OR;
    logic C6_1_NOR;
    logic AE_addr; //Used by AE logic and PAL16L6A_A1

    assign C7_1_OR = |cpuA_A[13:12];
    assign C6_1_NOR = ~(C7_1_OR | cpuA_A[11]);
    assign AE_addr = C6_1_NOR | C5_1_Y3n;
    
    assign AE = ~(AE_addr | cpuA_nMR); //C6_2_NOR;


    logic cpuB_NMI_TRIG_R_cpuA_NMI_ACK_W_CTRL;
    logic C2_2_INV; //Inverter
    logic C7_4_OR; //2-Input OR


    assign C2_2_INV = ~cpuA_A[11];
    assign C7_4_OR = |cpuA_A[13:12];

    //         1 1 1 1  1 | 1     |
    //Address: 5 4 3 2  1 | 0 9 8 | 7 6 5 4  3 2 1 0
    //16'hC000 1 1 0 0  0 | 0 0 0 | x x x x  x x x x COIN                               R
    //16'hC100 1 1 0 0  0 | 0 0 1 | x x x x  x x x x P1                                 R
    //16'hC200 1 1 0 0  0 | 0 1 0 | x x x x  x x x x P2                                 R    
    //16'hC300 1 1 0 0  0 | 0 1 1 | x x x x  x x x x P1_P2 (Not Used)                   -
    //16'hC400 1 1 0 0  0 | 1 0 0 | x x x x  x x x x MCODE                              W
    //16'hC500 1 1 0 0  0 | 1 0 1 | x x x x  x x x x DIP1                               R
    //16'hC600 1 1 0 0  0 | 1 1 0 | x x x x  x x x x DIP2                               R
    //16'hC700 1 1 0 0  0 | 1 1 1 | x x x x  x x x x cpuB_NMI_TRIG_R_cpuA_NMI_ACK_W_CTRL RW
    ttl_74138_nodly c8 (.Enable1_bar(C7_4_OR), .Enable2_bar(C7_3_OR), .Enable3(C2_2_INV), .A(cpuA_A[10:8]), 
                  .Y({cpuB_NMI_TRIG_R_cpuA_NMI_ACK_W_CTRL, DIP2, DIP1, MCODE, P1_P2, P2, P1, COIN}));
    //---------------------------------------------

    always @(posedge clk) begin
        //CPUA_RD <= cpuA_nRD;
        //CPUA_WR <= cpuA_nWR;
        if(!cpuA_nMR && !C5_1_Y3n) CPUAD <= cpuA_Dout;
        else CPUAD <= 8'hff;
    end
    //--- 27128 16Kx8 CPUA ROMS 250ns ---
    logic [7:0] data_P3_4H;
    logic [7:0] data_P2_4F;
    logic [7:0] data_P1_4E;
    
    eprom_16K P3_4H
    (
        .ADDR(cpuA_A[13:0]),
        .CLK(clk),
        .DATA(data_P3_4H),
        .ADDR_DL(ioctl_addr),
        .CLK_DL(clk),
        .DATA_IN(ioctl_data),
        .CS_DL(P3_4H_cs),
        .WR(ioctl_wr)
    );
    
    eprom_16K P2_4F
    (
        .ADDR(cpuA_A[13:0]),
        .CLK(clk),
        .DATA(data_P2_4F),
        .ADDR_DL(ioctl_addr),
        .CLK_DL(clk),
        .DATA_IN(ioctl_data),
        .CS_DL(P2_4F_cs),
        .WR(ioctl_wr)
    );
    
    eprom_16K P1_4E
    (
        .ADDR(cpuA_A[13:0]),
        .CLK(clk),
        .DATA(data_P1_4E),
        .ADDR_DL(ioctl_addr),
        .CLK_DL(clk),
        .DATA_IN(ioctl_data),
        .CS_DL(P1_4E_cs),
        .WR(ioctl_wr)
    );
    //---------------------------------

    //CPU A data input MUX
    always @(posedge clk) begin
             if(!CS_ROM_P3n && !cpuA_nMR)              cpuA_Din <= data_P3_4H;
        else if(!CS_ROM_P2n && !cpuA_nMR)              cpuA_Din <= data_P2_4F; 
        else if(!CS_ROM_P1n && !cpuA_nMR)              cpuA_Din <= data_P1_4E;
        //IO input         13    12      11       10      9         8    7654    3          2       1        0         
        //PLAYER1 = {2'b11,m_up1,m_down1,m_right1,m_left1,m_service,1'b1,rotary1,m_missile1,m_shot1,m_start1,m_coin};
        else if(!COIN)                                 cpuA_Din <= {2'b11,SND_BUSY,PLAYER2[1],PLAYER1[1],(PLAYER1[9] & PLAYER2[9]),1'b1,(PLAYER1[0] & PLAYER2[0])}; //{TEST_SW,UNK,SND_BUSY,START2,START1,SERVICE1,UNK,COIN}                       
        else if(!P1)                                   cpuA_Din <= {PLAYER1[7:4],PLAYER1[11],PLAYER1[10],PLAYER1[12],PLAYER1[13]}; //Player1 inputs:{1P3,1P2,1P1,1P0,RIGHT,LEFT,DOWN,UP}
        else if(!P2)                                   cpuA_Din <= {PLAYER2[7:4],PLAYER2[11],PLAYER2[10],PLAYER2[12],PLAYER2[13]}; //Player2 inputs:{2P3,2P2,2P1,2P0,RIGHT,LEFT,DOWN,UP}
        else if(!P1_P2)                                cpuA_Din <= {4'b1111,PLAYER2[3],PLAYER2[2],PLAYER1[3],PLAYER1[2]};  // P1/P2 Buttons:{UNK,UNK,UNK,UNK,2PUSH2,2PUSH1,1PUSH2,1PUSH1}
        else if(!DIP1)                                 cpuA_Din <= DSW[7:0]; //8'b1001_1100; //DSW[7:0]; //DIP1 Switches 
        else if(!DIP2)                                 cpuA_Din <= DSW[15:8]; //8'b1111_0111; //DSW[15:8];//DIP2 Switches
        else if(!cpuB_NMI_TRIG_R_cpuA_NMI_ACK_W_CTRL)  cpuA_Din <= 8'hFF; //C700 Read
        //VIDEO RAM & Regs.      
        else if(!VD_to_cpuAdbus)                       cpuA_Din <= cpuA_Vin;
        else                                           cpuA_Din <= 8'hFF;          
    end

    // ----------------- Z80B Cpu -----------------
    //output
    logic cpuB_nM1;
    logic cpuB_nMR;
    logic cpuB_nIO;
    logic cpuB_nRD;
    logic cpuB_nWR;
    logic cpuB_nRFSH;
    logic cpuB_nHALT;
    logic cpuB_nBUSACK;
    //input
    logic cpuB_nINT;
    logic cpuB_nNMI;
    logic cpuB_nBR = 1'b1;
    logic [15:0] cpuB_A; //BA

    logic E4_2_Qn;
    DFF_pseudoAsyncClrPre #(.W(1)) e4_2 (
        .clk(clk),
        .rst(~VIDEO_RSTn),
        .din(1'b1),
        .q(),
        .qn(cpuB_nINT),
        .set(1'b0),    // active high
        .clr(~cpuB_nIO),    // active high
        .cen(VBL) // signal whose edge will trigger the FF
    );

    logic  [7:0] cpuB_Din;
    logic  [7:0] cpuB_Dout;

    //T80pa CLK x4 real CPU clock
    T80pa z80_E1 (
    //tv80pa z80_E1 (
        .RESET_n(reset_n), //RESETn
        .CLK    (clk),
        .CEN_p  (Cen_p & ~pause_cpu), //active high
        .CEN_n  (Cen_n & ~pause_cpu), //active high
        //.WAIT_n (BWA | ~pause_cpu),
        .WAIT_n (BWA),
        .INT_n  (cpuB_nINT),
        .NMI_n  (cpuB_nNMI),
        .RD_n   (cpuB_nRD),
        .WR_n   (cpuB_nWR),
        .A      (cpuB_A),
        .DI     (cpuB_Din),
        .DO     (cpuB_Dout),
        .IORQ_n (cpuB_nIO),
        .M1_n   (cpuB_nM1),
        .MREQ_n (cpuB_nMR),
        .BUSRQ_n(1'b1),
        .BUSAK_n(cpuB_nBUSACK),
        .OUT0   (1'b0),
        .RFSH_n (cpuB_nRFSH),
        .HALT_n (cpuB_nHALT)
    );

    //---------------------------------------------
    //------------ CPUB Memory Mapper -------------
    logic C5_2_Y3n;
    logic CS_ROM_P6n;
    logic CS_ROM_P5n;
    logic CS_ROM_P4n;
    //              1 1 1 1  1 | 1     |
    //Address:      5 4 3 2  1 | 0 9 8 | 7 6 5 4  3 2 1 0
    //16'h0000-3FFF 0 0 x x  x | x x x | x x x x  x x x x CS_ROM_P4n  
    //16'h4000-7FFF 0 1 x x  x | x x x | x x x x  x x x x CS_ROM_P5n
    //16'h8000-BFFF 1 0 x x  x | x x x | x x x x  x x x x CS_ROM_P6n
    ttl_74139_nodly c5_2(.Enable_bar(1'b0), .A_2D(cpuB_A[15:14]), .Y_2D({C5_2_Y3n, CS_ROM_P6n, CS_ROM_P5n, CS_ROM_P4n}));
    
    //--- BE logic ---
    logic C4_1_OR;
    logic C6_4_NOR;
    logic BE_addr; ////C4_2_OR Used by BE logic, PAL16L6A_A1 and B6 LS373
    logic cpuA_NMI_TRIG_R_cpuB_NMI_ACK_W_CTRL;

    assign C4_1_OR = |cpuB_A[13:12];
    assign C6_4_NOR = ~(C4_1_OR | cpuB_A[11]);
    assign BE_addr = C6_4_NOR | C5_2_Y3n; 
    assign BE = ~(BE_addr | cpuB_nMR); //C6_3_NOR;
    //-----------------

    //---------------------------------------------
    //--- 27128 16Kx8 CPUB ROMS 250ns ---
    logic [7:0] data_P6_2H;
    logic [7:0] data_P5_2F;
    logic [7:0] data_P4_2E;

    eprom_16K P6_2H
    (
        .ADDR(cpuB_A[13:0]),
        .CLK(clk),
        .DATA(data_P6_2H),
        .ADDR_DL(ioctl_addr),
        .CLK_DL(clk),
        .DATA_IN(ioctl_data),
        .CS_DL(P6_2H_cs),
        .WR(ioctl_wr)
    );

    eprom_16K P5_2F
    (
        .ADDR(cpuB_A[13:0]),
        .CLK(clk),
        .DATA(data_P5_2F),
        .ADDR_DL(ioctl_addr),
        .CLK_DL(clk),
        .DATA_IN(ioctl_data),
        .CS_DL(P5_2F_cs),
        .WR(ioctl_wr)
    );

    eprom_16K P4_2E
    (
        .ADDR(cpuB_A[13:0]),
        .CLK(clk),
        .DATA(data_P4_2E),
        .ADDR_DL(ioctl_addr),
        .CLK_DL(clk),
        .DATA_IN(ioctl_data),
        .CS_DL(P4_2E_cs),
        .WR(ioctl_wr)
    );

    //---------------------------------
    //CPU B data input
    always @(posedge clk) begin
        if(!CS_ROM_P6n && !cpuB_nMR)                          cpuB_Din <= data_P6_2H;
        else if(!CS_ROM_P5n && !cpuB_nMR)                          cpuB_Din <= data_P5_2F; 
        else if(!CS_ROM_P4n && !cpuB_nMR)                          cpuB_Din <= data_P4_2E;
        //hack to assign 0xFF value to data bus when reads addresses 0xC000.
        else if(!cpuA_NMI_TRIG_R_cpuB_NMI_ACK_W_CTRL && !cpuB_nRD) cpuB_Din <= 8'hFF;    
        //VIDEO RAM & Regs     
        else if(!VD_to_cpuBdbus)                                   cpuB_Din <= cpuB_Vin;
        else                                                       cpuB_Din <= 8'hFF; 
    end

    //--- cpuA and cpuB interrupt logic ---
    logic cpuB_NMI_TRIG_R; //B3_4_OR;
    logic cpuA_NMI_ACK_W;  //B3_3_OR;
    
    assign cpuB_NMI_TRIG_R = cpuB_NMI_TRIG_R_cpuA_NMI_ACK_W_CTRL | cpuA_nRD; //R
    assign cpuA_NMI_ACK_W  = cpuB_NMI_TRIG_R_cpuA_NMI_ACK_W_CTRL | cpuA_nWR;  //W

    logic C4_4_OR;
    logic C3_2_3NOR;
    logic C3_1_3NOR;
    logic C3_3_3NOR;

    //         1 1 1 1  1 | 1     |
    //Address: 5 4 3 2  1 | 0 9 8 | 7 6 5 4  3 2 1 0
    //16'hC000 1 1 0 0  0 | 0 0 0 | x x x x  x x x x cpuA_NMI_TRIG_R_cpuB_NMI_ACK_W_CTRL RW
    assign C4_4_OR                               = cpuB_A[12] | cpuB_A[11];  //|cpuB_A[12:11];
    assign C3_2_3NOR                             = ~(C4_4_OR | cpuB_A[13] | C5_2_Y3n);
    assign cpuA_NMI_TRIG_R_cpuB_NMI_ACK_W_CTRL   = ~C3_2_3NOR; //C2_1_INV
    
    assign C3_3_3NOR = ~(cpuA_NMI_TRIG_R_cpuB_NMI_ACK_W_CTRL | cpuB_nMR | cpuB_nRD); //R
    assign C3_1_3NOR = ~(cpuA_NMI_TRIG_R_cpuB_NMI_ACK_W_CTRL | cpuB_nMR | cpuB_nWR); //W

    logic cpuB_NMI_ACK_W;  //C2_4_INV
    logic cpuA_NMI_TRIG_R; //C2_6_INV

    assign cpuA_NMI_TRIG_R = ~C3_3_3NOR; //C2_6_INV
    assign cpuB_NMI_ACK_W  = ~C3_1_3NOR;  //C2_4_INV

    DFF_pseudoAsyncClrPre #(.W(1)) c1_1 (
        .clk(clk),
        .rst(~VIDEO_RSTn),
        .din(1'b1),
        .q(),
        .qn(cpuA_nNMI),
        .set(1'b0),    // active high
        .clr(~cpuA_NMI_ACK_W),    // active high
        .cen(cpuA_NMI_TRIG_R) // signal whose edge will trigger the FF
    );

    DFF_pseudoAsyncClrPre #(.W(1)) c1_2 (
        .clk(clk),
        .rst(~VIDEO_RSTn),
        .din(1'b1),
        .q(),
        .qn(cpuB_nNMI),
        .set(1'b0),    // active high
        .clr(~cpuB_NMI_ACK_W),    // active high
        .cen(cpuB_NMI_TRIG_R) // signal whose edge will trigger the FF
    );
    //------------------------------------



    //--- Common cpuA and cpuB memory mapper ---
    //                1 1 1 1  1 | 1     |
    //Address:        5 4 3 2  1 | 0 9 8 | 7 6 5 4  3 2 1 0
    //16'hD000-D7FF   1 1 0 1  0 | x x x | x x x x  x x x x cpuA SHARED FRONT VIDEO RAM 2Kbytes
    //16'hC800-CFFF   1 1 0 0  1 | x x x | x x x x  x x x x cpuB SHARED FRONT VIDEO RAM 2Kbytes
    //16'hF800-FFFF   1 1 1 1  1 | x x x | x x x x  x x x x SHARED SIDE_VIDEO_RAM cpuA 2Kbytes
    //16'hF800-FFFF   1 1 1 1  1 | x x x | x x x x  x x x x SHARED SIDE_VIDEO_RAM cpuB 2Kbytes
    //16'hD800-DFFF   1 1 0 1  1 | x x x | x x x x  x x x x BACK1 VIDEO RAM BANK 0 cpuA
    //16'hE000-E7FF   1 1 1 0  0 | x x x | x x x x  x x x x BACK1 VIDEO RAM BANK 1 cpuA
    //16'hE800-EFFF   1 1 1 0  1 | x x x | x x x x  x x x x BACK1 VIDEO RAM BANK 2 cpuA
    //16'hF000-F7FF   1 1 1 1  0 | x x x | x x x x  x x x x BACK1 VIDEO RAM BANK 3 cpuA
    //16'hD000-D7FF   1 1 0 1  0 | x x x | x x x x  x x x x BACK1 VIDEO RAM BANK 0 cpuB
    //16'hD800-DFFF   1 1 0 1  1 | x x x | x x x x  x x x x BACK1 VIDEO RAM BANK 1 cpuB
    //16'hE000-E7FF   1 1 1 0  0 | x x x | x x x x  x x x x BACK1 VIDEO RAM BANK 2 cpuB
    //16'hE800-EFFF   1 1 1 0  1 | x x x | x x x x  x x x x BACK1 VIDEO RAM BANK 3 cpuB
    A5001_2 C4(
        //inputs
        .AMRn(cpuA_nMR), //1
        .AE_addr(AE_addr), //2 
        .A_addr13(cpuA_A[13]), //3
        .A_addr12(cpuA_A[12]),  //4
        .A_addr11(cpuA_A[11]), //5
        .BMRn(cpuB_nMR),     //6
        .BE_addr(BE_addr), //7
        .B_addr13(cpuB_A[13]), //8
        .B_addr12(cpuB_A[12]), //9 
        .B_addr11(cpuB_A[11]), //10
        .ARDn(cpuA_nRD), //11
        .BRDn(cpuB_nRD), //13
        .AB_Sel(A_B), //22
        //outputs
        .VA12(VA[12]),
        .FRONT_VIDEO_CSn(FRONT_VIDEO_CSn), //16 F1C
        .VRDn(VRDn), //17
        .SIDE_VRAM_CSn(SIDE_VRAM_CSn), //19 SC
        .DISC(DISC), //20 DISC
        .BACK1_VRAM_CSn(BACK1_VRAM_CSn) //B1C
    );  

    assign VD_to_cpuAdbus = cpuA_nRD | AE_addr;
    assign VD_to_cpuBdbus = cpuB_nRD | BE_addr;
    //-----------------------------------------

    //ttl_74157 A_2D({B3,A3,B2,A2,B1,A1,B0,A0})
    ttl_74157 #(.DELAY_RISE(0), .DELAY_FALL(0)) A4 (.Enable_bar(1'b0), .Select(A_B),
                .A_2D({cpuB_A[3],cpuA_A[3],cpuB_A[2],cpuA_A[2],cpuB_A[1],cpuA_A[1],cpuB_A[0],cpuA_A[0]}), .Y(VA[3:0]));

    ttl_74157 #(.DELAY_RISE(0), .DELAY_FALL(0)) B4 (.Enable_bar(1'b0), .Select(A_B),
                .A_2D({cpuB_A[7],cpuA_A[7],cpuB_A[6],cpuA_A[6],cpuB_A[5],cpuA_A[5],cpuB_A[4],cpuA_A[4]}), .Y(VA[7:4]));

    //TNKIII uses ~A[11] for cpuA
    ttl_74157 #(.DELAY_RISE(0), .DELAY_FALL(0)) A3 (.Enable_bar(1'b0), .Select(A_B),
                .A_2D({cpuB_A[11],~cpuA_A[11],cpuB_A[10],cpuA_A[10],cpuB_A[9],cpuA_A[9],cpuB_A[8],cpuA_A[8]}), .Y(VA[11:8]));

    //ONLY WRITABLE VIDEO RELATED REGISTERS (TNKIII)
    //              1 1 1 1  1 | 1     |
    //Address:      5 4 3 2  1 | 0 9 8 | 7 6 5 4  3 2 1 0
    //16'hC800      1 1 0 0  1 | 0 0 0 | x x x x  x x x x MSB
    //16'hC900      1 1 0 0  1 | 0 0 1 | x x x x  x x x x FSX
    //16'hCA00      1 1 0 0  1 | 0 1 0 | x x x x  x x x x FSY
    //16'hCB00      1 1 0 0  1 | 0 1 1 | x x x x  x x x x B1SX
    //16'hCC00      1 1 0 0  1 | 1 0 0 | x x x x  x x x x B1SY
    //16'hCD00      1 1 0 0  1 | 1 0 1 | x x x x  x x x x -
    //16'hCE00      1 1 0 0  1 | 1 1 0 | x x x x  x x x x -
    //16'hCF00      1 1 0 0  1 | 1 1 1 | x x x x  x x x x COIN COUNTERS nopw() in MAME
    logic B3_Y5, B3_Y6;
    ttl_74138_nodly B3(
        .Enable1_bar(DISC), //4 G2An
        .Enable2_bar(VDG), //5 G2Bn
        .Enable3(1'b1), //6 G1
        .A(VA[10:8]), //3,2,1 C,B,A
        .Y({COIN_COUNTERS, B3_Y6, B3_Y5, B1SY, B1SX, FSY, FSX, MSB}) //7,9,10,11,12,13,14,15 Y[7:0]
    );


    //------------------------------------------

    //--- VD common data bus RW control ---
    // Data out 
    // Vout <- WBB or WBA
    assign V_out = ((!WBA) ? CPUAD : ( 
                    (!WBB) ? cpuB_Dout : 8'hff ));

    logic [7:0] cpuA_Vin_r, cpuB_Vin_r;
    // data in (modeled as a latch with independent output enabled control)
    always @(posedge clk) begin
        if(!VIDEO_RSTn) begin
            cpuA_Vin_r <= 0;
            cpuB_Vin_r <= 0;
        end
        else begin
            if (RLA) //transparent latch (sync with clk)
                cpuA_Vin_r <= V_in;
            else
                cpuA_Vin_r <= cpuA_Vin; 

            if (RLB) //transparent latch (sync with clk)
                cpuB_Vin_r <= V_in;
            else
                cpuB_Vin_r <= cpuB_Vin;
        end
    end
    assign cpuA_Vin = (!VD_to_cpuAdbus) ? cpuA_Vin_r : 8'hff;
    assign cpuB_Vin = (!VD_to_cpuBdbus) ? cpuB_Vin_r : 8'hff;
endmodule
