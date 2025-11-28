`resetall
`default_nettype none

module m_dmem #(
    parameter DMEM_ADDRW = `DMEM_ADDRW,
    parameter DMEM_ENTRIES = `DMEM_ENTRIES
) (
    input  wire        clk_i,
    input  wire        rea_i,
    input  wire        reb_i,
    input  wire        wea_i,
    input  wire        web_i,
    input  wire [DMEM_ADDRW-1:0] addra_i,
    input  wire [DMEM_ADDRW-1:0] addrb_i,
    input  wire [31:0] wdataa_i,
    input  wire [31:0] wdatab_i,
    input  wire [ 3:0] wstrba_i,
    input  wire [ 3:0] wstrbb_i,
    output wire [31:0] rdataa_o,
    output wire [31:0] rdatab_o
);

    (* ram_style = "block" *) reg [31:0] dmem[0:DMEM_ENTRIES-1];
    `include "memd.txt"

    reg [31:0] rdataa = 0;
    always @(posedge clk_i) begin
        if (wea_i) begin
            if (wstrba_i[0]) dmem[addra_i][7:0] <= wdataa_i[7:0];
            if (wstrba_i[1]) dmem[addra_i][15:8] <= wdataa_i[15:8];
            if (wstrba_i[2]) dmem[addra_i][23:16] <= wdataa_i[23:16];
            if (wstrba_i[3]) dmem[addra_i][31:24] <= wdataa_i[31:24];
        end
        if (rea_i) rdataa <= dmem[addra_i];
    end
    assign rdataa_o = rdataa;

    reg [31:0] rdatab = 0;
    always @(posedge clk_i) begin
        if (web_i) begin
            if (wstrbb_i[0]) dmem[addrb_i][7:0] <= wdatab_i[7:0];
            if (wstrbb_i[1]) dmem[addrb_i][15:8] <= wdatab_i[15:8];
            if (wstrbb_i[2]) dmem[addrb_i][23:16] <= wdatab_i[23:16];
            if (wstrbb_i[3]) dmem[addrb_i][31:24] <= wdatab_i[31:24];
        end
        if (reb_i) rdatab <= dmem[addrb_i];
    end
    assign rdatab_o = rdatab;
endmodule

`resetall
