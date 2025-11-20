`resetall
`default_nettype none

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

`resetall
