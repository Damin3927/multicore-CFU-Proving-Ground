`resetall
`default_nettype none

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

`resetall
