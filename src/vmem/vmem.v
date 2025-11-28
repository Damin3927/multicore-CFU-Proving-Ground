`resetall
`default_nettype none

module vmem #(
    parameter VMEM_ADDRW = `VMEM_ADDRW,
    parameter VMEM_ENTRIES = `VMEM_ENTRIES
) (
    input  wire                   clk_i,
    input  wire                   we_i,
    input  wire [VMEM_ADDRW-1:0] waddr_i,
    input  wire             [2:0] wdata_i,
    input  wire [VMEM_ADDRW-1:0] raddr_i,
    output wire             [2:0] rdata_o
);

    reg [2:0] vmem[0:VMEM_ENTRIES-1];
    integer i;
    initial begin
        for (i = 0; i < VMEM_ENTRIES; i = i + 1) begin
            vmem[i] = 0;
        end
    end

    reg                  we;
    reg            [2:0] wdata;
    reg [VMEM_ADDRW-1:0] waddr;
    reg [VMEM_ADDRW-1:0] raddr;
    reg            [2:0] rdata;

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
    reg  [VMEM_ADDRW-1:0] r_adr_p = 0;
    reg  [VMEM_ADDRW-1:0] r_dat_p = 0;

    wire [VMEM_ADDRW-1:0] data = {{5{wdata_i[2]}}, {6{wdata_i[1]}}, {5{wdata_i[0]}}};
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

`resetall
