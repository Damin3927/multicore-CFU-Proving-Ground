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
    //    wire rst_ni = 1;
    reg rst_ni = 0;
    initial #15 rst_ni = 1;
    wire clk, locked;

`ifdef SYNTHESIS
    clk_wiz_0 clk_wiz_0 (
        .clk_out1(clk),      // output clk_out1
        .reset   (!rst_ni),  // input reset
        .locked  (locked),   // output locked
        .clk_in1 (clk_i)     // input clk_in1
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

    wire [31:0] hart_rdata[0:`NCORES-1];

    wire        dmem_we   [0:`NCORES-1];
    wire [31:0] dmem_addr [0:`NCORES-1];
    wire [31:0] dmem_wdata[0:`NCORES-1];
    wire [3:0]  dmem_wstrb[0:`NCORES-1];
    wire [31:0] dmem_rdata[0:`NCORES-1];

    wire        vmem_we     = dbus_we[0] & (dbus_addr[0][29]);
    wire [15:0] vmem_addr   = dbus_addr[0][15:0];
    wire [2:0]  vmem_wdata  = dbus_wdata[0][2:0];

    genvar i;
    generate
        for (i = 0; i < `NCORES; i = i + 1) begin
            reg [1:0]                   rdata_sel = 0;
            always @(posedge clk) begin
                if (!dbus_addr[i][30]) rdata_sel <= 0;      // dmem
                else if (!dbus_addr[i][12]) rdata_sel <= 1;  // perf
                else rdata_sel <= 2;                         // hart
            end
            wire [31:0] perf_rdata;
            assign dbus_rdata[i] = (rdata_sel == 0) ? dmem_rdata[i] :
                                (rdata_sel == 1) ? perf_rdata :
                                hart_rdata[i];
            cpu cpu (
                .clk_i        (clk),            // input  wire
                .rst_i        (rst),            // input  wire
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

            assign dmem_we[i]     = dbus_we[i] & (dbus_addr[i][28]);
            assign dmem_addr[i]   = dbus_addr[i];
            assign dmem_wdata[i]  = dbus_wdata[i];
            assign dmem_wstrb[i]  = dbus_wstrb[i];

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

    m_imem imem (
        .clka_i  (clk),            // input  wire
        .clkb_i  (clk),            // input  wire
        .raddra_i(imem_raddr[0]),  // input  wire [ADDR_WIDTH-1:0]
        .raddrb_i(imem_raddr[1]),  // input  wire [ADDR_WIDTH-1:0]
        .rdataa_o(imem_rdata[0]),  // output wire [DATA_WIDTH-1:0]
        .rdatab_o(imem_rdata[1])   // output wire [DATA_WIDTH-1:0]
    );

    m_dmem dmem (
        .clka_i  (clk),            // input  wire
        .clkb_i  (clk),            // input  wire
        .wea_i   (dmem_we[0]),     // input  wire                  
        .web_i   (dmem_we[1]),     // input  wire
        .addra_i (dmem_addr[0]),   // input  wire [ADDR_WIDTH-1:0] 
        .addrb_i (dmem_addr[1]),   // input  wire [ADDR_WIDTH-1:0] 
        .wdataa_i(dmem_wdata[0]),  // input  wire [DATA_WIDTH-1:0] 
        .wdatab_i(dmem_wdata[1]),  // input  wire [DATA_WIDTH-1:0] 
        .wstrba_i(dmem_wstrb[0]),  // input  wire [STRB_WIDTH-1:0] 
        .wstrbb_i(dmem_wstrb[1]),  // input  wire [STRB_WIDTH-1:0] 
        .rdataa_o(dmem_rdata[0]),  // output reg  [DATA_WIDTH-1:0] 
        .rdatab_o(dmem_rdata[1])   // output reg  [DATA_WIDTH-1:0] 
    );

    wire [15:0] vmem_raddr;
    wire [2:0] vmem_rdata_t;
    vmem vmem (
        .clk_i  (clk),            // input  wire
        .we_i   (vmem_we),        // input  wire                  
        .waddr_i (vmem_addr),     // input  wire [15:0] 
        .wdata_i(vmem_wdata),     // input  wire [2:0] 
        .raddr_i (vmem_raddr),    // input  wire [15:0]
        .rdata_o (vmem_rdata_t)   // output wire [2:0]
    );

    wire [15:0] vmem_rdata = {{5{vmem_rdata_t[2]}}, {6{vmem_rdata_t[1]}}, {5{vmem_rdata_t[0]}}};
    m_st7789_disp st7789_disp (
        .w_clk     (clk),         // input  wire
        .st7789_SDA(st7789_SDA),  // output wire
        .st7789_SCL(st7789_SCL),  // output wire
        .st7789_DC (st7789_DC),   // output wire
        .st7789_RES(st7789_RES),  // output wire
        .w_raddr   (vmem_raddr),  // output wire [15:0]
        .w_rdata   (vmem_rdata)  // input  wire [15:0]
    );

endmodule

module m_imem (
    input  wire        clka_i,
    input  wire        clkb_i,
    input  wire [31:0] raddra_i,
    input  wire [31:0] raddrb_i,
    output wire [31:0] rdataa_o,
    output wire [31:0] rdatab_o
);
    (* ram_style = "block" *) reg [31:0] imem[0:`IMEM_ENTRIES-1];
    `include "memi.txt"

    wire [`IMEM_ADDRW-1:0] valid_raddra = raddra_i[`IMEM_ADDRW+1:2];
    wire [`IMEM_ADDRW-1:0] valid_raddrb = raddrb_i[`IMEM_ADDRW+1:2];

    reg [31:0] rdataa;
    always @(posedge clka_i) begin
        rdataa <= imem[valid_raddra];
    end
    assign rdataa_o = rdataa;

    reg [31:0] rdatab;
    always @(posedge clkb_i) begin
        rdatab <= imem[valid_raddrb];
    end
    assign rdatab_o = rdatab;
endmodule

module m_dmem (
    input  wire        clka_i,
    input  wire        clkb_i,
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
    always @(posedge clka_i) begin
        if (wea_i) begin  ///// data bus
            if (wstrba_i[0]) dmem[valid_addra][7:0] <= wdataa_i[7:0];
            if (wstrba_i[1]) dmem[valid_addra][15:8] <= wdataa_i[15:8];
            if (wstrba_i[2]) dmem[valid_addra][23:16] <= wdataa_i[23:16];
            if (wstrba_i[3]) dmem[valid_addra][31:24] <= wdataa_i[31:24];
        end
        rdataa <= dmem[valid_addra];
    end
    assign rdataa_o = rdataa;

    reg [31:0] rdatab = 0;
    always @(posedge clkb_i) begin
        if (web_i) begin  ///// data bus
            if (wstrbb_i[0]) dmem[valid_addrb][7:0] <= wdatab_i[7:0];
            if (wstrbb_i[1]) dmem[valid_addrb][15:8] <= wdatab_i[15:8];
            if (wstrbb_i[2]) dmem[valid_addrb][23:16] <= wdatab_i[23:16];
            if (wstrbb_i[3]) dmem[valid_addrb][31:24] <= wdatab_i[31:24];
        end
        rdatab <= dmem[valid_addrb];
    end
    assign rdatab_o = rdatab;
endmodule

module perf_cntr (
    input  wire        clk_i,
    input  wire [ 3:0] addr_i,
    input  wire [ 2:0] wdata_i,
    input  wire        w_en_i,
    output wire [31:0] rdata_o
);
    reg [63:0] mcycle = 0;
    reg [ 1:0] cnt_ctrl = 0;
    reg [31:0] rdata = 0;

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
    input  wire [ 2:0] wdata_i,
    input  wire [15:0] raddr_i,
    output wire [ 2:0] rdata_o
);

    reg [2:0] vmem_lo[0:32767];  // vmem
    reg [2:0] vmem_hi[0:32767];  // vmem
    integer i;
    initial
        for (i = 0; i < 32768; i = i + 1) begin
            vmem_lo[i] = 0;
            vmem_hi[i] = 0;
        end

    reg        we;
    reg        top;
    reg [ 2:0] wdata;
    reg [14:0] waddr;

    reg        rtop;
    reg [14:0] raddr;
    reg [ 2:0] rdata_lo;
    reg [ 2:0] rdata_hi;
    reg        sel;

    localparam ADDR_MASK = 16'h7FFF;

    always @(posedge clk_i) begin
        we <= we_i;
        top <= waddr_i[15];
        waddr <= waddr_i[14:0];
        wdata <= wdata_i;

        rtop <= raddr_i[15];
        raddr <= raddr_i[14:0];

        if (we) begin
            if (top) vmem_hi[waddr&ADDR_MASK] <= wdata;
            else vmem_lo[waddr&ADDR_MASK] <= wdata;
        end

        sel <= rtop;
        rdata_lo <= vmem_lo[raddr&ADDR_MASK];
        rdata_hi <= vmem_hi[raddr&ADDR_MASK];
    end

    assign rdata_o = (sel) ? rdata_hi : rdata_lo;


`ifndef SYNTHESIS
    reg  [15:0] r_adr_p = 0;
    reg  [15:0] r_dat_p = 0;

    wire [15:0] data = {{5{wdata_i[2]}}, {6{wdata_i[1]}}, {5{wdata_i[0]}}};
    always @(posedge clk_i)
        if (we_i) begin
            case (waddr_i[15])
                0:
                if (vmem_lo[waddr_i&ADDR_MASK] != wdata_i) begin
                    r_adr_p <= waddr_i;
                    r_dat_p <= data;
                    $write("@D%0d_%0d\n", waddr_i ^ r_adr_p, data ^ r_dat_p);
                    $fflush();
                end
                1:
                if (vmem_hi[waddr_i&ADDR_MASK] != wdata_i) begin
                    r_adr_p <= waddr_i;
                    r_dat_p <= data;
                    $write("@D%0d_%0d\n", waddr_i ^ r_adr_p, data ^ r_dat_p);
                    $fflush();
                end
            endcase
        end
`endif

endmodule

module m_st7789_disp (
    input wire w_clk,  // main clock signal (100MHz)
    output wire st7789_SDA,
    output wire st7789_SCL,
    output wire st7789_DC,
    output wire st7789_RES,
    output wire [15:0] w_raddr,
    input wire [15:0] w_rdata
);
    reg [31:0] r_cnt = 1;
    always @(posedge w_clk) r_cnt <= (r_cnt == 0) ? 0 : r_cnt + 1;
    reg r_RES = 1;
    always @(posedge w_clk) begin
        r_RES <= (r_cnt == 100000) ? 0 : (r_cnt == 200000) ? 1 : r_RES;
    end
    assign st7789_RES = r_RES;

    wire busy;
    reg r_en = 0;
    reg init_done = 0;
    reg [4:0] r_state = 0;
    reg [19:0] r_state2 = 0;
    reg [8:0] r_dat = 0;
    reg [15:0] r_c = 16'hf800;

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
    reg [7:0] r_cnt = 0;
    reg r_SCL = 1;
    reg r_DC = 0;
    reg [7:0] r_data = 0;
    reg r_SDA = 0;

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
