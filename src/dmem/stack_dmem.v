`resetall
`default_nettype none

module stack_dmem #(
    parameter STACK_ADDRW = `STACK_ADDRW,
    parameter STACK_ENTRIES = `STACK_ENTRIES
) (
    input  wire           clk_i,
    input  wire           re_i,
    input  wire           we_i,
    input  wire [STACK_ADDRW-1:0] addr_i,
    input  wire [31:0]    wdata_i,
    input  wire [3:0]     wstrb_i,
    output wire [31:0]    rdata_o
);
    (* ram_style = "block" *) reg [31:0] mem[0:STACK_ENTRIES-1];

    reg [31:0] rdata = 0;
    always @(posedge clk_i) begin
        if (we_i) begin
            if (wstrb_i[0]) mem[addr_i][7:0]   <= wdata_i[7:0];
            if (wstrb_i[1]) mem[addr_i][15:8]  <= wdata_i[15:8];
            if (wstrb_i[2]) mem[addr_i][23:16] <= wdata_i[23:16];
            if (wstrb_i[3]) mem[addr_i][31:24] <= wdata_i[31:24];
        end
        if (re_i) rdata <= mem[addr_i];
    end

    assign rdata_o = rdata;
endmodule

`resetall
