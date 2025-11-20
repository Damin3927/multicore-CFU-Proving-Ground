`resetall
`default_nettype none

module perf_cntr (
    input  wire        clk_i,
    input  wire        rst_i,
    input  wire  [7:0] addr_i,
    input  wire  [2:0] wdata_i,
    input  wire        w_en_i,
    input  wire        insnret,
    output wire [31:0] rdata_o
);
    reg [63:0] mcycle   = 0;
    reg  [1:0] cnt_ctrl = 0;
    reg [31:0] rdata    = 0;

    reg [63:0] r_insnret = 0;
    always @(posedge clk_i) begin
        r_insnret <= (rst_i) ? 0 : (insnret) ? r_insnret + 1 : r_insnret;
    end

    always @(posedge clk_i) begin
        rdata <= (addr_i == 8'h04) ? mcycle[31:0]  :
                 (addr_i == 8'h08) ? mcycle[63:32] :
                 (addr_i == 8'h10) ? r_insnret[31:0] : r_insnret[63:32];
        if (w_en_i && addr_i == 0) cnt_ctrl <= wdata_i[1:0];
        case (cnt_ctrl)
            0: mcycle <= 0;
            1: mcycle <= mcycle + 1;
            default: ;
        endcase
    end

    assign rdata_o = rdata;
endmodule

`resetall
