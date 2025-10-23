/* CFU Proving Ground since 2025-02    Copyright(c) 2025 Archlab. Science Tokyo /
/ Released under the MIT license https://opensource.org/licenses/mit           */

`resetall `default_nettype none

`include "config.vh"

module main (
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

    wire                        rst = !rst_ni || !locked;
    wire [`IBUS_ADDR_WIDTH-1:0] imem_raddr [0:`NCORES-1];
    wire [`IBUS_DATA_WIDTH-1:0] imem_rdata [0:`NCORES-1];
    wire                        dbus_we   [0:`NCORES-1];
    wire [`DBUS_ADDR_WIDTH-1:0] dbus_addr [0:`NCORES-1];
    wire [`DBUS_DATA_WIDTH-1:0] dbus_wdata[0:`NCORES-1];
    wire [`DBUS_STRB_WIDTH-1:0] dbus_wstrb[0:`NCORES-1];
    wire [`DBUS_DATA_WIDTH-1:0] dbus_rdata[0:`NCORES-1];
    wire                        dbus_stall[0:`NCORES-1];

    wire [31:0] hart_rdata[0:`NCORES-1];

    wire        dmem_we   [0:`NCORES-1];
    wire        dmem_re   [0:`NCORES-1];
    wire [31:0] dmem_addr [0:`NCORES-1];
    wire [31:0] dmem_wdata[0:`NCORES-1];
    wire [3:0]  dmem_wstrb[0:`NCORES-1];
    wire [31:0] dmem_rdata[0:`NCORES-1];

    // Pack arrays for dbus_dmem module
    wire [`NCORES-1:0] dmem_re_packed;
    wire [`NCORES-1:0] dmem_we_packed;
    wire [32*`NCORES-1:0] dmem_addr_packed;
    wire [32*`NCORES-1:0] dmem_wdata_packed;
    wire [4*`NCORES-1:0] dmem_wstrb_packed;
    wire [32*`NCORES-1:0] dmem_rdata_packed;
    wire [`NCORES-1:0] dbus_stall_packed;

    genvar pack_idx;
    generate
        for (pack_idx = 0; pack_idx < `NCORES; pack_idx = pack_idx + 1) begin
            assign dmem_re_packed[pack_idx] = dmem_re[pack_idx];
            assign dmem_we_packed[pack_idx] = dmem_we[pack_idx];
            assign dmem_addr_packed[32*(pack_idx+1)-1:32*pack_idx] = dmem_addr[pack_idx];
            assign dmem_wdata_packed[32*(pack_idx+1)-1:32*pack_idx] = dmem_wdata[pack_idx];
            assign dmem_wstrb_packed[4*(pack_idx+1)-1:4*pack_idx] = dmem_wstrb[pack_idx];
            assign dmem_rdata[pack_idx] = dmem_rdata_packed[32*(pack_idx+1)-1:32*pack_idx];
            assign dbus_stall[pack_idx] = dbus_stall_packed[pack_idx];
        end
    endgenerate

    wire        vmem_we     = dbus_we[0] & (dbus_addr[0][29]);
    wire [15:0] vmem_addr   = dbus_addr[0][15:0];
    wire [2:0]  vmem_wdata  = dbus_wdata[0][2:0];

    genvar i;
    generate
        for (i = 0; i < `NCORES; i = i + 1) begin : gen_cpu
            // Memory map address decoding:
            // 0x10000000 - 0x10003FFF (bit[28]=1, bit[29]=0, bit[30]=0): Data Memory
            // 0x20000000 - 0x2000FFFF (bit[29]=1, bit[30]=0): Video Memory
            // 0x40000000 - 0x40000FFF (bit[30]=1, bit[12]=0): Performance Counter
            // 0x40001000 - 0x40001FFF (bit[30]=1, bit[12]=1): Hart Index
            wire in_dmem_range = (dbus_addr[i][30:28] == 3'b001);  // 0x1xxxxxxx
            wire in_vmem_range = (dbus_addr[i][30:28] == 3'b010);  // 0x2xxxxxxx
            wire in_perf_range = (dbus_addr[i][30:28] == 3'b100) && !dbus_addr[i][12];  // 0x40000xxx
            wire in_hart_range = (dbus_addr[i][30:28] == 3'b100) && dbus_addr[i][12];   // 0x40001xxx

            wire [1:0] rdata_sel_next = in_dmem_range ? 2'd0 :
                                        in_vmem_range ? 2'd1 :
                                        in_perf_range ? 2'd2 :
                                        in_hart_range ? 2'd3 : 2'd0;

            reg [1:0] rdata_sel = 0;
            always @(posedge clk) begin
                rdata_sel <= rdata_sel_next;
            end

            wire [31:0] perf_rdata;
            assign dbus_rdata[i] = (rdata_sel == 2'd0) ? dmem_rdata[i] :
                                   (rdata_sel == 2'd1) ? 0 :  // unused for vmem
                                   (rdata_sel == 2'd2) ? perf_rdata :
                                   (rdata_sel == 2'd3) ? hart_rdata[i] : 0;
            cpu cpu (
                .clk_i        (clk),            // input  wire
                .rst_i        (rst),            // input  wire
                .stall_i      (dbus_stall[i]),  // input  wire
                .ibus_araddr_o(imem_raddr[i]),  // output wire [`IBUS_ADDR_WIDTH-1:0]
                .ibus_rdata_i (imem_rdata[i]),  // input  wire [`IBUS_DATA_WIDTH-1:0]
                .dbus_addr_o  (dbus_addr[i]),   // output wire [`DBUS_ADDR_WIDTH-1:0]
                .dbus_wvalid_o(dbus_we[i]),     // output wire
                .dbus_wdata_o (dbus_wdata[i]),  // output wire [`DBUS_DATA_WIDTH-1:0]
                .dbus_wstrb_o (dbus_wstrb[i]),  // output wire [`DBUS_STRB_WIDTH-1:0]
                .dbus_rdata_i (dbus_rdata[i]),  // input  wire [`DBUS_DATA_WIDTH-1:0]
                .hart_index   (i)               // input  wire
            );

            assign hart_rdata[i] = i;

            assign dmem_re[i]     = rdata_sel_next == 2'd0 ? !dbus_we[i] & (dbus_addr[i][28]) : 0;
            assign dmem_we[i]     = rdata_sel_next == 2'd0 ? dbus_we[i] & (dbus_addr[i][28]) : 0;
            assign dmem_addr[i]   = rdata_sel_next == 2'd0 ? dbus_addr[i] : 0;
            assign dmem_wdata[i]  = rdata_sel_next == 2'd0 ? dbus_wdata[i] : 0;
            assign dmem_wstrb[i]  = rdata_sel_next == 2'd0 ? dbus_wstrb[i] : 0;

            wire perf_we = dbus_we[i] & (dbus_addr[i][30]) & (!dbus_addr[i][12]);
            wire [3:0] perf_addr = dbus_addr[i][3:0];
            wire [2:0] perf_wdata = dbus_wdata[i][2:0];
            perf_cntr perf (
                .clk_i  (clk),         // input  wire
                .addr_i (perf_addr),   // input  wire [3:0]
                .wdata_i(perf_wdata),  // input  wire [2:0]
                .w_en_i (perf_we),     // input  wire
                .rdata_o(perf_rdata)   // output wire [31:0]
            );
        end
    endgenerate

    genvar imem_idx;
    generate
        for (imem_idx = 0; imem_idx < (`NCORES+1)/2; imem_idx = imem_idx + 1) begin : gen_imem
            if (imem_idx*2 + 1 < `NCORES) begin
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

    dbus_dmem dbus_dmem (
        .clk_i         (clk),                // input  wire
        .re_packed_i   (dmem_re_packed),     // input  wire [NCORES-1:0]
        .we_packed_i   (dmem_we_packed),     // input  wire [NCORES-1:0]
        .addr_packed_i (dmem_addr_packed),   // input  wire [32*NCORES-1:0]
        .wdata_packed_i(dmem_wdata_packed),  // input  wire [32*NCORES-1:0]
        .wstrb_packed_i(dmem_wstrb_packed),  // input  wire [4*NCORES-1:0]
        .rdata_packed_o(dmem_rdata_packed),  // output wire [32*NCORES-1:0]
        .stall_packed_o(dbus_stall_packed)   // output wire [NCORES-1:0]
    );

    wire [15:0] vmem_raddr;
    wire  [2:0] vmem_rdata_t;
    vmem vmem (
        .clk_i   (clk),          // input wire
        .we_i    (vmem_we),      // input wire
        .waddr_i (vmem_addr),    // input wire [15:0]
        .wdata_i (vmem_wdata),   // input wire [15:0]
        .raddr_i (vmem_raddr),   // input wire [15:0]
        .rdata_o (vmem_rdata_t)  // output wire [15:0]
    );

    wire [15:0] vmem_rdata = {{5{vmem_rdata_t[2]}}, {6{vmem_rdata_t[1]}}, {5{vmem_rdata_t[0]}}};
    m_st7789_disp st7789_disp (
        .w_clk      (clk),         // input  wire
        .st7789_SDA (st7789_SDA),  // output wire
        .st7789_SCL (st7789_SCL),  // output wire
        .st7789_DC  (st7789_DC),   // output wire
        .st7789_RES (st7789_RES),  // output wire
        .w_raddr    (vmem_raddr),  // output wire [15:0]
        .w_rdata    (vmem_rdata)   // input  wire [15:0]
    );

endmodule

module m_imem (
    input  wire        clk_i,
    input  wire [31:0] raddra_i,
    input  wire [31:0] raddrb_i,
    output wire [31:0] rdataa_o,
    output wire [31:0] rdatab_o
);
    (* ram_style = "block" *) reg [31:0] imem[0:`IMEM_ENTRIES-1];
    `include "memi.txt"

    wire [`IMEM_ADDRW-1:0] valid_raddra = raddra_i[`IMEM_ADDRW+1:2];
    wire [`IMEM_ADDRW-1:0] valid_raddrb = raddrb_i[`IMEM_ADDRW+1:2];

    reg [31:0] rdataa = 0;
    always @(posedge clk_i) begin
        rdataa <= imem[valid_raddra];
    end
    assign rdataa_o = rdataa;

    reg [31:0] rdatab = 0;
    always @(posedge clk_i) begin
        rdatab <= imem[valid_raddrb];
    end
    assign rdatab_o = rdatab;
endmodule

module dbus_dmem #(
    parameter NCORES = `NCORES
) (
    input wire clk_i,
    input wire [NCORES-1:0] re_packed_i,
    input wire [NCORES-1:0] we_packed_i,
    input wire [32*NCORES-1:0] addr_packed_i,
    input wire [32*NCORES-1:0] wdata_packed_i,
    input wire [4*NCORES-1:0] wstrb_packed_i,
    output wire [32*NCORES-1:0] rdata_packed_o,
    output wire [NCORES-1:0] stall_packed_o
);
    // Round-robin arbiter for multi-core dmem access
    genvar i;

    // Unpack input arrays
    wire        re   [0:NCORES-1];
    wire        we   [0:NCORES-1];
    wire [31:0] addr [0:NCORES-1];
    wire [31:0] wdata[0:NCORES-1];
    wire [3:0]  wstrb[0:NCORES-1];
    wire [31:0] rdata[0:NCORES-1];
    wire        stall[0:NCORES-1];
    reg  [31:0] rdata_reg [0:NCORES-1];
    reg         stall_o   [0:NCORES-1];

    generate
        for (i = 0; i < NCORES; i = i + 1) begin : unpack_arrays
            assign re[i]    = re_packed_i[i];
            assign we[i]    = we_packed_i[i];
            assign addr[i]  = addr_packed_i[32*(i+1)-1:32*i];
            assign wdata[i] = wdata_packed_i[32*(i+1)-1:32*i];
            assign wstrb[i] = wstrb_packed_i[4*(i+1)-1:4*i];
            assign rdata_packed_o[32*(i+1)-1:32*i] = rdata_reg[i];
            assign stall_packed_o[i] = stall_o[i];
        end
    endgenerate

    always @(posedge clk_i) begin
        for (j = 0; j < NCORES; j = j + 1) begin
            stall_o[j] <= stall[j];
        end
    end

    // Reserved request registers for each core
    reg        req_valid [0:NCORES-1];  // request is pending
    reg        req_re [0:NCORES-1];
    reg        req_we [0:NCORES-1];
    reg [31:0] req_addr [0:NCORES-1];
    reg [31:0] req_wdata [0:NCORES-1];
    reg [3:0]  req_wstrb [0:NCORES-1];

    // Round-robin state
    reg [$clog2(NCORES)-1:0] rr_ptr = 0;  // points to next core to serve

    // Select up to 2 cores to service this cycle
    reg [$clog2(NCORES)-1:0] sel_core_a; // first selected core index
    reg [$clog2(NCORES)-1:0] sel_core_b; // second selected core index
    reg sel_valid_a;                     // if a port is selected or not
    reg sel_valid_b;                     // if b port is selected or not

    // Reserve incoming requests - all requests go through the buffer
    integer j;
    always @(posedge clk_i) begin : reserve_requests_block
        for (j = 0; j < NCORES; j = j + 1) begin
            // Set valid if new request arrives
            if (!req_valid[j]) begin
                req_valid[j] <= addr[j] != 32'h0;  // new request
                req_re[j]    <= re[j];
                req_we[j]    <= we[j];
                req_addr[j]  <= addr[j];
                req_wdata[j] <= wdata[j];
                req_wstrb[j] <= wstrb[j];
            end else if (being_served[j]) begin
                // Clear valid when being served
                req_valid[j] <= 1'b0;
                req_re[j]    <= 1'b0;
                req_we[j]    <= 1'b0;
                req_addr[j]  <= 32'h0;
                req_wdata[j] <= 32'h0;
                req_wstrb[j] <= 4'h0;
            end
        end
    end

    generate
        for (i = 0; i < NCORES; i = i + 1) begin : gen_output
            assign stall[i] = (addr[i] != 0) // new request arrives
                            || (req_valid[i]); // pending request
            assign rdata[i] = (resp_valid_a && resp_core_a == i) ? rdataa_dmem :
                              (resp_valid_b && resp_core_b == i) ? rdatab_dmem : 32'h0;
        end
    endgenerate

    always @(posedge clk_i) begin
        for (j = 0; j < NCORES; j = j + 1) begin
            rdata_reg[j] <= rdata[j];
        end
    end

    // Combinational logic to select cores in round-robin fashion
    integer k, m;
    always @(*) begin : select_cores_block
        sel_valid_a = 1'b0;
        sel_valid_b = 1'b0;
        sel_core_a = 0;
        sel_core_b = 0;

        // Find first pending request starting from rr_ptr
        for (k = 0; k < NCORES; k = k + 1) begin
            if (req_valid[(rr_ptr + k) % NCORES] && !sel_valid_a) begin
                sel_core_a = (rr_ptr + k) % NCORES;
                sel_valid_a = 1'b1;
            end
        end

        // Find second pending request (different from first)
        for (m = 0; m < NCORES; m = m + 1) begin
            if (req_valid[(rr_ptr + m) % NCORES] && !sel_valid_b && ((rr_ptr + m) % NCORES) != sel_core_a) begin
                sel_core_b = (rr_ptr + m) % NCORES;
                sel_valid_b = 1'b1;
            end
        end
    end

    // Track which cores are currently being served (data will be ready next cycle)
    wire being_served [0:NCORES-1];
    generate
        for (i = 0; i < NCORES; i = i + 1) begin : gen_being_served
            assign being_served[i] = (sel_valid_a && sel_core_a == i) || (sel_valid_b && sel_core_b == i);
        end
    endgenerate

    // Connect to dmem ports - use buffered requests
    wire rea_int           = sel_valid_a && req_re[sel_core_a];
    wire reb_int           = sel_valid_b && req_re[sel_core_b];
    wire wea_int           = sel_valid_a && req_we[sel_core_a];
    wire web_int           = sel_valid_b && req_we[sel_core_b];
    wire [31:0] addra_int  = sel_valid_a ? req_addr[sel_core_a]  : 0;
    wire [31:0] addrb_int  = sel_valid_b ? req_addr[sel_core_b]  : 0;
    wire [31:0] wdataa_int = sel_valid_a ? req_wdata[sel_core_a] : 0;
    wire [31:0] wdatab_int = sel_valid_b ? req_wdata[sel_core_b] : 0;
    wire [3:0]  wstrba_int = sel_valid_a ? req_wstrb[sel_core_a] : 0;
    wire [3:0]  wstrbb_int = sel_valid_b ? req_wstrb[sel_core_b] : 0;

    wire [31:0] rdataa_dmem;
    wire [31:0] rdatab_dmem;

    // Pipeline for tracking which core's data is coming
    reg [$clog2(NCORES)-1:0] resp_core_a;
    reg [$clog2(NCORES)-1:0] resp_core_b;
    reg resp_valid_a;
    reg resp_valid_b;

    always @(posedge clk_i) begin
        resp_core_a  <= sel_core_a;
        resp_core_b  <= sel_core_b;
        resp_valid_a <= sel_valid_a;
        resp_valid_b <= sel_valid_b;
    end

    // Update round-robin pointer
    always @(posedge clk_i) begin
        if (sel_valid_a && sel_valid_b) begin
            rr_ptr <= (sel_core_b + 1) % NCORES;
        end else if (sel_valid_a) begin
            rr_ptr <= (sel_core_a + 1) % NCORES;
        end
    end

    m_dmem dmem (
        .clk_i   (clk_i),            // input  wire
        .rea_i   (rea_int),          // input  wire
        .reb_i   (reb_int),          // input  wire
        .wea_i   (wea_int),          // input  wire
        .web_i   (web_int),          // input  wire
        .addra_i (addra_int),        // input  wire [ADDR_WIDTH-1:0]
        .addrb_i (addrb_int),        // input  wire [ADDR_WIDTH-1:0]
        .wdataa_i(wdataa_int),       // input  wire [DATA_WIDTH-1:0]
        .wdatab_i(wdatab_int),       // input  wire [DATA_WIDTH-1:0]
        .wstrba_i(wstrba_int),       // input  wire [STRB_WIDTH-1:0]
        .wstrbb_i(wstrbb_int),       // input  wire [STRB_WIDTH-1:0]
        .rdataa_o(rdataa_dmem),      // output wire [DATA_WIDTH-1:0]
        .rdatab_o(rdatab_dmem)       // output wire [DATA_WIDTH-1:0]
    );
endmodule

module m_dmem (
    input  wire        clk_i,
    input  wire        rea_i,
    input  wire        reb_i,
    input  wire        wea_i,
    input  wire        web_i,
    input  wire [31:0] addra_i,
    input  wire [31:0] addrb_i,
    input  wire [31:0] wdataa_i,
    input  wire [31:0] wdatab_i,
    input  wire [ 3:0] wstrba_i,
    input  wire [ 3:0] wstrbb_i,
    output wire [31:0] rdataa_o,
    output wire [31:0] rdatab_o
);

    (* ram_style = "block" *) reg [31:0] dmem[0:`DMEM_ENTRIES-1];
    `include "memd.txt"

    wire [`DMEM_ADDRW-1:0] valid_addra = addra_i[`DMEM_ADDRW+1:2];
    wire [`DMEM_ADDRW-1:0] valid_addrb = addrb_i[`DMEM_ADDRW+1:2];

    reg [31:0] rdataa = 0;
    always @(posedge clk_i) begin
        if (wea_i) begin
            if (wstrba_i[0]) dmem[valid_addra][7:0] <= wdataa_i[7:0];
            if (wstrba_i[1]) dmem[valid_addra][15:8] <= wdataa_i[15:8];
            if (wstrba_i[2]) dmem[valid_addra][23:16] <= wdataa_i[23:16];
            if (wstrba_i[3]) dmem[valid_addra][31:24] <= wdataa_i[31:24];
        end
        if (rea_i) rdataa <= dmem[valid_addra];
    end
    assign rdataa_o = rdataa;

    reg [31:0] rdatab = 0;
    always @(posedge clk_i) begin
        if (web_i) begin
            if (wstrbb_i[0]) dmem[valid_addrb][7:0] <= wdatab_i[7:0];
            if (wstrbb_i[1]) dmem[valid_addrb][15:8] <= wdatab_i[15:8];
            if (wstrbb_i[2]) dmem[valid_addrb][23:16] <= wdatab_i[23:16];
            if (wstrbb_i[3]) dmem[valid_addrb][31:24] <= wdatab_i[31:24];
        end
        if (reb_i) rdatab <= dmem[valid_addrb];
    end
    assign rdatab_o = rdatab;
endmodule

module perf_cntr (
    input  wire        clk_i,
    input  wire  [3:0] addr_i,
    input  wire  [2:0] wdata_i,
    input  wire        w_en_i,
    output wire [31:0] rdata_o
);
    reg [63:0] mcycle   = 0;
    reg  [1:0] cnt_ctrl = 0;
    reg [31:0] rdata    = 0;

    always @(posedge clk_i) begin
        rdata <= (addr_i[2]) ? mcycle[31:0] : mcycle[63:32];
        if (w_en_i && addr_i == 0) cnt_ctrl <= wdata_i[1:0];
        case (cnt_ctrl)
            0: mcycle <= 0;
            1: mcycle <= mcycle + 1;
            default: ;
        endcase
    end

    assign rdata_o = rdata;
endmodule

module vmem (
    input  wire        clk_i,
    input  wire        we_i,
    input  wire [15:0] waddr_i,
    input  wire  [2:0] wdata_i,
    input  wire [15:0] raddr_i,
    output wire  [2:0] rdata_o
);

    reg [2:0] vmem[0:65535];
    integer i;
    initial begin
        for (i = 0; i < 65536; i = i + 1) begin
            vmem[i] = 0;
        end
    end

    reg        we;
    reg  [2:0] wdata;
    reg [15:0] waddr;
    reg [15:0] raddr;
    reg  [2:0] rdata;

    always @(posedge clk_i) begin
        we    <= we_i;
        waddr <= waddr_i;
        wdata <= wdata_i;
        raddr <= raddr_i;

        if (we) begin
            vmem[waddr] <= wdata;
        end

        rdata <= vmem[raddr];
    end

    assign rdata_o = rdata;

`ifndef SYNTHESIS
    reg  [15:0] r_adr_p = 0;
    reg  [15:0] r_dat_p = 0;

    wire [15:0] data = {{5{wdata_i[2]}}, {6{wdata_i[1]}}, {5{wdata_i[0]}}};
    always @(posedge clk_i)
        if (we_i) begin
            if (vmem[waddr_i] != wdata_i) begin
                r_adr_p <= waddr_i;
                r_dat_p <= data;
                $write("@D%0d_%0d\n", waddr_i ^ r_adr_p, data ^ r_dat_p);
                $fflush();
            end
        end
`endif
endmodule

module m_st7789_disp (
    input  wire        w_clk,  // main clock signal (100MHz)
    output wire        st7789_SDA,
    output wire        st7789_SCL,
    output wire        st7789_DC,
    output wire        st7789_RES,
    output wire [15:0] w_raddr,
    input  wire [15:0] w_rdata
);
    reg [31:0] r_cnt = 1;
    always @(posedge w_clk) r_cnt <= (r_cnt == 0) ? 0 : r_cnt + 1;
    reg r_RES = 1;
    always @(posedge w_clk) begin
        r_RES <= (r_cnt == 100000) ? 0 : (r_cnt == 200000) ? 1 : r_RES;
    end
    assign st7789_RES = r_RES;

    wire       busy;
    reg        r_en      = 0;
    reg        init_done = 0;
    reg  [4:0] r_state   = 0;
    reg [19:0] r_state2  = 0;
    reg  [8:0] r_dat     = 0;
    reg [15:0] r_c       = 16'hf800;

    reg [31:0] r_bcnt = 0;
    always @(posedge w_clk) r_bcnt <= (busy) ? 0 : r_bcnt + 1;

    always @(posedge w_clk)
        if (!init_done) begin
            r_en <= (r_cnt > 1000000 && !busy && r_bcnt > 1000000);
        end else begin
            r_en <= (!busy);
        end

    always @(posedge w_clk) if (r_en && !init_done) r_state <= r_state + 1;

    always @(posedge w_clk)
        if (r_en && init_done) begin
            r_state2 <= (r_state2==115210) ? 0 : r_state2 + 1; // 11 + 240x240*2 = 11 + 115200 = 115211
        end

    reg [7:0] r_x = 0;
    reg [7:0] r_y = 0;
    always @(posedge w_clk)
        if (r_en && init_done && r_state2[0] == 1) begin
            r_x <= (r_state2 < 11 || r_x == 239) ? 0 : r_x + 1;
            r_y <= (r_state2 < 11) ? 0 : (r_x == 239) ? r_y + 1 : r_y;
        end

    wire [7:0] w_nx = 239 - r_x;
    wire [7:0] w_ny = 239 - r_y;
    assign w_raddr = (`LCD_ROTATE == 0) ? {r_y, r_x} :  // default
        (`LCD_ROTATE == 1) ? {r_x, w_ny} :  // 90 degree rotation
        (`LCD_ROTATE == 2) ? {w_ny, w_nx} : {w_nx, r_y};  //180 degree, 240 degree rotation

    reg [15:0] r_color = 0;
    always @(posedge w_clk) r_color <= w_rdata;

    always @(posedge w_clk) begin
        case (r_state2)  /////
            0: r_dat <= {1'b0, 8'h2A};  // Column Address Set
            1: r_dat <= {1'b1, 8'h00};  // [0]
            2: r_dat <= {1'b1, 8'h00};  // [0]
            3: r_dat <= {1'b1, 8'h00};  // [0]
            4: r_dat <= {1'b1, 8'd239};  // [239]
            5: r_dat <= {1'b0, 8'h2B};  // Row Address Set
            6: r_dat <= {1'b1, 8'h00};  // [0]
            7: r_dat <= {1'b1, 8'h00};  // [0]
            8: r_dat <= {1'b1, 8'h00};  // [0]
            9: r_dat <= {1'b1, 8'd239};  // [239]
            10: r_dat <= {1'b0, 8'h2C};  // Memory Write
            default: r_dat <= (r_state2[0]) ? {1'b1, r_color[15:8]} : {1'b1, r_color[7:0]};
        endcase
    end

    reg [8:0] r_init = 0;
    always @(posedge w_clk) begin
        case (r_state)  /////
            0: r_init <= {1'b0, 8'h01};  // Software Reset, wait 120msec
            1: r_init <= {1'b0, 8'h11};  // Sleep Out, wait 120msec
            2: r_init <= {1'b0, 8'h3A};  // Interface Pixel Format
            3: r_init <= {1'b1, 8'h55};  // [65K RGB, 16bit/pixel]
            4: r_init <= {1'b0, 8'h36};  // Memory Data Accell Control
            5: r_init <= {1'b1, 8'h00};  // [000000]
            6: r_init <= {1'b0, 8'h21};  // Display Inversion On
            7: r_init <= {1'b0, 8'h13};  // Normal Display Mode On
            8: r_init <= {1'b0, 8'h29};  // Display On
            9: init_done <= 1;
        endcase
    end

    wire [8:0] w_data = (init_done) ? r_dat : r_init;
    m_spi spi0 (
        w_clk,
        r_en,
        w_data,
        st7789_SDA,
        st7789_SCL,
        st7789_DC,
        busy
    );
endmodule

/****** SPI send module,  SPI_MODE_2, MSBFIRST                                           *****/
/*********************************************************************************************/
module m_spi (
    input  wire       w_clk,  // 100MHz input clock !!
    input  wire       en,     // write enable
    input  wire [8:0] d_in,   // data in
    output wire       SDA,    // Serial Data
    output wire       SCL,    // Serial Clock
    output wire       DC,     // Data/Control
    output wire       busy    // busy
);
    reg [5:0] r_state = 0;
    reg [7:0] r_cnt   = 0;
    reg       r_SCL   = 1;
    reg       r_DC    = 0;
    reg [7:0] r_data  = 0;
    reg       r_SDA   = 0;

    always @(posedge w_clk) begin
        if (en && r_state == 0) begin
            r_state <= 1;
            r_data  <= d_in[7:0];
            r_DC    <= d_in[8];
            r_cnt   <= 0;
        end else if (r_state == 1) begin
            r_SDA   <= r_data[7];
            r_data  <= {r_data[6:0], 1'b0};
            r_state <= 2;
            r_cnt   <= r_cnt + 1;
        end else if (r_state == 2) begin
            r_SCL   <= 0;
            r_state <= 3;
        end else if (r_state == 3) begin
            r_state <= 4;
        end else if (r_state == 4) begin
            r_SCL   <= 1;
            r_state <= (r_cnt == 8) ? 0 : 1;
        end
    end

    assign SDA  = r_SDA;
    assign SCL  = r_SCL;
    assign DC   = r_DC;
    assign busy = (r_state != 0 || en);
endmodule
/*********************************************************************************************/
`resetall
