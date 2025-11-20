`resetall
`default_nettype none

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

`resetall
