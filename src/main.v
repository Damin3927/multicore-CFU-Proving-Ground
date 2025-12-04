/* CFU Proving Ground since 2025-02    Copyright(c) 2025 Archlab. Science Tokyo /
/ Released under the MIT license https://opensource.org/licenses/mit           */

`resetall `default_nettype none

`include "config.vh"

module main #(
    parameter IBUS_ADDR_WIDTH = `IBUS_ADDR_WIDTH,
    parameter IBUS_DATA_WIDTH = `IBUS_DATA_WIDTH,
    parameter DBUS_ADDR_WIDTH = `DBUS_ADDR_WIDTH,
    parameter DBUS_DATA_WIDTH = `DBUS_DATA_WIDTH,
    parameter DBUS_STRB_WIDTH = `DBUS_STRB_WIDTH,
    parameter DMEM_ADDRW = `DMEM_ADDRW,
    parameter VMEM_ADDRW = `VMEM_ADDRW,
    parameter NCORES     = `NCORES
) (
    input  wire clk_i,
    output wire st7789_SDA,
    output wire st7789_SCL,
    output wire st7789_DC,
    output wire st7789_RES
);
    reg rst_ni = 0; initial #15 rst_ni = 1;
    wire clk, locked;

`ifdef SYNTHESIS
    clk_wiz_0 clk_wiz_0 (
        .clk_out1 (clk),      // output clk_out1
        .reset    (!rst_ni),  // input reset
        .locked   (locked),   // output locked
        .clk_in1  (clk_i)     // input clk_in1
    );
`else
    assign clk    = clk_i;
    assign locked = 1'b1;
`endif

    wire                       rst = !rst_ni || !locked;
    wire [IBUS_ADDR_WIDTH-1:0] imem_raddr [0:NCORES-1];
    wire [IBUS_DATA_WIDTH-1:0] imem_rdata [0:NCORES-1];
    wire                       dbus_we   [0:NCORES-1];
    wire [DBUS_ADDR_WIDTH-1:0] dbus_addr [0:NCORES-1];
    wire [DBUS_DATA_WIDTH-1:0] dbus_wdata[0:NCORES-1];
    wire [DBUS_STRB_WIDTH-1:0] dbus_wstrb[0:NCORES-1];
    wire                       dbus_is_lr[0:NCORES-1];
    wire                       dbus_is_sc[0:NCORES-1];
    wire [DBUS_DATA_WIDTH-1:0] dbus_rdata[0:NCORES-1];
    wire                       dbus_stall[0:NCORES-1];

    wire [31:0] hart_rdata[0:NCORES-1];

    wire                       dmem_we    [0:NCORES-1];
    wire                       dmem_re    [0:NCORES-1];
    wire [DMEM_ADDRW-1:0]      dmem_addr  [0:NCORES-1];
    wire                [31:0] dmem_wdata [0:NCORES-1];
    wire                [3:0]  dmem_wstrb [0:NCORES-1];
    wire                [31:0] dmem_rdata [0:NCORES-1];

    wire                  vmem_we    [0:NCORES-1];
    wire [VMEM_ADDRW-1:0] vmem_addr  [0:NCORES-1];
    wire           [31:0] vmem_wdata [0:NCORES-1];

    // Pack arrays for dbus_dmem module
    wire [NCORES-1:0] dmem_re_packed;
    wire [NCORES-1:0] dmem_we_packed;
    wire [DMEM_ADDRW*NCORES-1:0] dmem_addr_packed;
    wire [32*NCORES-1:0] dmem_wdata_packed;
    wire [4*NCORES-1:0] dmem_wstrb_packed;
    wire [NCORES-1:0] dmem_is_lr_packed;
    wire [NCORES-1:0] dmem_is_sc_packed;
    wire [32*NCORES-1:0] dmem_rdata_packed;
    wire [NCORES-1:0] dbus_stall_packed;

    // Pack arrays for dbus_vmem module
    wire [NCORES-1:0] vmem_we_packed;
    wire [VMEM_ADDRW*NCORES-1:0] vmem_addr_packed;
    wire [32*NCORES-1:0] vmem_wdata_packed;
    wire [NCORES-1:0] vmem_stall_packed;

    genvar pack_idx;
    generate
        for (pack_idx = 0; pack_idx < NCORES; pack_idx = pack_idx + 1) begin
            assign dmem_re_packed[pack_idx] = dmem_re[pack_idx];
            assign dmem_we_packed[pack_idx] = dmem_we[pack_idx];
            assign dmem_addr_packed[DMEM_ADDRW*(pack_idx+1)-1:DMEM_ADDRW*pack_idx] = dmem_addr[pack_idx];
            assign dmem_wdata_packed[32*(pack_idx+1)-1:32*pack_idx] = dmem_wdata[pack_idx];
            assign dmem_wstrb_packed[4*(pack_idx+1)-1:4*pack_idx] = dmem_wstrb[pack_idx];
            assign dmem_is_lr_packed[pack_idx] = dbus_is_lr[pack_idx];
            assign dmem_is_sc_packed[pack_idx] = dbus_is_sc[pack_idx];
            assign dmem_rdata[pack_idx] = dmem_rdata_packed[32*(pack_idx+1)-1:32*pack_idx];
            assign dbus_stall[pack_idx] = dbus_stall_packed[pack_idx] | vmem_stall_packed[pack_idx];

            assign vmem_we_packed[pack_idx] = vmem_we[pack_idx];
            assign vmem_addr_packed[VMEM_ADDRW*(pack_idx+1)-1:VMEM_ADDRW*pack_idx] = vmem_addr[pack_idx];
            assign vmem_wdata_packed[32*(pack_idx+1)-1:32*pack_idx] = vmem_wdata[pack_idx];
        end
    endgenerate

    genvar i;
    generate
        for (i = 0; i < NCORES; i = i + 1) begin : gen_cpu
            // Memory map address decoding:
            // 0x10000000 - 0x10003FFF (bit[28]=1, bit[29]=0, bit[30]=0): Data Memory
            // 0x20000000 - 0x2000FFFF (bit[29]=1, bit[30]=0): Video Memory
            // 0x40000000 - 0x40000FFF (bit[30]=1, bit[12]=0): Performance Counter
            // 0x40001000 - 0x40001FFF (bit[30]=1, bit[12]=1): Hart Index
            wire in_dmem_range = dbus_addr[i][28];  // 0x1xxxxxxx
            wire in_vmem_range = dbus_addr[i][29];  // 0x2xxxxxxx
            wire in_perf_range = dbus_addr[i][30] && !dbus_addr[i][12];  // 0x40000xxx
            wire in_hart_range = dbus_addr[i][30] && dbus_addr[i][12];   // 0x40001xxx

            reg in_dmem_range_reg;
            reg in_vmem_range_reg;
            reg in_perf_range_reg;
            reg in_hart_range_reg;

            always @(posedge clk) begin
                in_dmem_range_reg <= in_dmem_range;
                in_vmem_range_reg <= in_vmem_range;
                in_perf_range_reg <= in_perf_range;
                in_hart_range_reg <= in_hart_range;
            end

            wire [31:0] perf_rdata;
            assign dbus_rdata[i] = in_dmem_range_reg ? dmem_rdata[i] :
                                   in_vmem_range_reg ? 0 :  // vmem is write-only for CPUs
                                   in_perf_range_reg ? perf_rdata :
                                   in_hart_range_reg ? hart_rdata[i] : dmem_rdata[i];

            wire insnret;

            cpu cpu (
                .clk_i        (clk),            // input  wire
                .rst_i        (rst),            // input  wire
                .stall_i      (dbus_stall[i]),  // input  wire
                .ibus_araddr_o(imem_raddr[i]),  // output wire [IBUS_ADDR_WIDTH-1:0]
                .ibus_rdata_i (imem_rdata[i]),  // input  wire [IBUS_DATA_WIDTH-1:0]
                .dbus_addr_o  (dbus_addr[i]),   // output wire [DBUS_ADDR_WIDTH-1:0]
                .dbus_wvalid_o(dbus_we[i]),     // output wire
                .dbus_wdata_o (dbus_wdata[i]),  // output wire [DBUS_DATA_WIDTH-1:0]
                .dbus_wstrb_o (dbus_wstrb[i]),  // output wire [DBUS_STRB_WIDTH-1:0]
                .dbus_is_lr_o (dbus_is_lr[i]),  // output wire
                .dbus_is_sc_o (dbus_is_sc[i]),  // output wire
                .dbus_rdata_i (dbus_rdata[i]),  // input  wire [DBUS_DATA_WIDTH-1:0]
                .insnret      (insnret),        // output wire
                .hart_index   (i)               // input  wire
            );

            assign hart_rdata[i] = i;

            assign dmem_re[i]    = in_dmem_range & !dbus_we[i];
            assign dmem_we[i]    = in_dmem_range & dbus_we[i];
            assign dmem_addr[i]  = in_dmem_range ? dbus_addr[i][DMEM_ADDRW+1:2] : 0;
            assign dmem_wdata[i] = in_dmem_range ? dbus_wdata[i] : 0;
            assign dmem_wstrb[i] = in_dmem_range ? dbus_wstrb[i] : 0;
            assign vmem_we[i]    = in_vmem_range & dbus_we[i];
            assign vmem_addr[i]  = in_vmem_range ? dbus_addr[i][VMEM_ADDRW-1:0] : 0;
            assign vmem_wdata[i] = in_vmem_range ? dbus_wdata[i] : 0;

            wire perf_we          = in_perf_range & dbus_we[i];
            wire [7:0] perf_addr  = dbus_addr[i][7:0];
            wire [2:0] perf_wdata = dbus_wdata[i][2:0];
            perf_cntr perf (
                .clk_i   (clk),         // input  wire
                .rst_i   (rst),         // input  wire
                .addr_i  (perf_addr),   // input  wire [7:0]
                .wdata_i (perf_wdata),  // input  wire [2:0]
                .w_en_i  (perf_we),     // input  wire
                .insnret (insnret),     // input  wire
                .rdata_o (perf_rdata)   // output wire [31:0]
            );
        end
    endgenerate

    genvar imem_idx;
    generate
        for (imem_idx = 0; imem_idx < (NCORES+1)/2; imem_idx = imem_idx + 1) begin : gen_imem
            if (imem_idx*2 + 1 < NCORES) begin
                m_imem imem (
                    .clk_i  (clk),                          // input  wire
                    .raddra_i(imem_raddr[imem_idx*2]),      // input  wire [ADDR_WIDTH-1:0]
                    .raddrb_i(imem_raddr[imem_idx*2 + 1]),  // input  wire [ADDR_WIDTH-1:0]
                    .rdataa_o(imem_rdata[imem_idx*2]),      // output wire [DATA_WIDTH-1:0]
                    .rdatab_o(imem_rdata[imem_idx*2 + 1])   // output wire [DATA_WIDTH-1:0]
                );
            end else begin
                // Last imem when NCORES is odd: only port A used
                m_imem imem (
                    .clk_i  (clk),                          // input  wire
                    .raddra_i(imem_raddr[imem_idx*2]),      // input  wire [ADDR_WIDTH-1:0]
                    .raddrb_i(32'h0),                       // input  wire [ADDR_WIDTH-1:0] (unused)
                    .rdataa_o(imem_rdata[imem_idx*2]),      // output wire [DATA_WIDTH-1:0]
                    .rdatab_o()                             // output wire [DATA_WIDTH-1:0] (unused)
                );
            end
        end
    endgenerate

`ifdef USE_COMB_DBUS
    comb_dbus_dmem comb_dbus_dmem (
        .clk_i         (clk),                // input  wire
        .re_packed_i   (dmem_re_packed),     // input  wire [NCORES-1:0]
        .we_packed_i   (dmem_we_packed),     // input  wire [NCORES-1:0]
        .addr_packed_i (dmem_addr_packed),   // input  wire [32*NCORES-1:0]
        .wdata_packed_i(dmem_wdata_packed),  // input  wire [32*NCORES-1:0]
        .wstrb_packed_i(dmem_wstrb_packed),  // input  wire [4*NCORES-1:0]
        .is_lr_packed_i(dmem_is_lr_packed),  // input  wire [NCORES-1:0]
        .is_sc_packed_i(dmem_is_sc_packed),  // input  wire [NCORES-1:0]
        .rdata_packed_o(dmem_rdata_packed),  // output wire [32*NCORES-1:0]
        .stall_packed_o(dbus_stall_packed)   // output wire [NCORES-1:0]
    );
`else
    dbus_dmem dbus_dmem (
        .clk_i         (clk),                // input  wire
        .re_packed_i   (dmem_re_packed),     // input  wire [NCORES-1:0]
        .we_packed_i   (dmem_we_packed),     // input  wire [NCORES-1:0]
        .addr_packed_i (dmem_addr_packed),   // input  wire [32*NCORES-1:0]
        .wdata_packed_i(dmem_wdata_packed),  // input  wire [32*NCORES-1:0]
        .wstrb_packed_i(dmem_wstrb_packed),  // input  wire [4*NCORES-1:0]
        .is_lr_packed_i(dmem_is_lr_packed),  // input  wire [NCORES-1:0]
        .is_sc_packed_i(dmem_is_sc_packed),  // input  wire [NCORES-1:0]
        .rdata_packed_o(dmem_rdata_packed),  // output wire [32*NCORES-1:0]
        .stall_packed_o(dbus_stall_packed)   // output wire [NCORES-1:0]
    );
`endif

    wire [VMEM_ADDRW-1:0] vmem_disp_raddr;
    wire            [2:0] vmem_disp_rdata_t;
    wire [VMEM_ADDRW-1:0] vmem_disp_rdata = {{5{vmem_disp_rdata_t[2]}}, {6{vmem_disp_rdata_t[1]}}, {5{vmem_disp_rdata_t[0]}}};

    dbus_vmem dbus_vmem (
        .clk_i          (clk),                // input  wire
        .we_packed_i    (vmem_we_packed),     // input  wire [NCORES-1:0]
        .addr_packed_i  (vmem_addr_packed),   // input  wire [32*NCORES-1:0]
        .wdata_packed_i (vmem_wdata_packed),  // input  wire [32*NCORES-1:0]
        .stall_packed_o (vmem_stall_packed),  // output wire [NCORES-1:0]
        .disp_raddr_i   (vmem_disp_raddr),    // input  wire [`VMEM_ADDRW-1:0]
        .disp_rdata_o   (vmem_disp_rdata_t)   // output wire [2:0]
    );

    m_st7789_disp st7789_disp (
        .w_clk      (clk),               // input  wire
        .st7789_SDA (st7789_SDA),        // output wire
        .st7789_SCL (st7789_SCL),        // output wire
        .st7789_DC  (st7789_DC),         // output wire
        .st7789_RES (st7789_RES),        // output wire
        .w_raddr    (vmem_disp_raddr),   // output wire [`VMEM_ADDRW-1:0]
        .w_rdata    (vmem_disp_rdata)    // input  wire [`VMEM_ADDRW-1:0]
    );

endmodule

`resetall
