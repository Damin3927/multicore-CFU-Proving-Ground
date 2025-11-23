`resetall
`default_nettype none

`include "config.vh"

module dbus_vmem #(
    parameter NCORES = `NCORES
) (
    input wire clk_i,
    input wire [NCORES-1:0] we_packed_i,
    input wire [32*NCORES-1:0] addr_packed_i,
    input wire [32*NCORES-1:0] wdata_packed_i,
    output wire [NCORES-1:0] stall_packed_o,
    input wire [`VMEM_ADDRW-1:0] disp_raddr_i,
    output wire [2:0] disp_rdata_o
);
    genvar i;

    // Unpack input arrays
    wire        we   [0:NCORES-1];
    wire [31:0] addr [0:NCORES-1];
    wire [31:0] wdata[0:NCORES-1];
    wire        stall[0:NCORES-1];
    reg         stall_o   [0:NCORES-1];

    generate
        for (i = 0; i < NCORES; i = i + 1) begin : unpack_arrays
            assign we[i]    = we_packed_i[i];
            assign addr[i]  = addr_packed_i[32*(i+1)-1:32*i];
            assign wdata[i] = wdata_packed_i[32*(i+1)-1:32*i];
            assign stall_packed_o[i] = stall_o[i];
        end
    endgenerate

    integer j;
    always @(posedge clk_i) begin
        for (j = 0; j < NCORES; j = j + 1) begin
            stall_o[j] <= stall[j];
        end
    end

    // Reserved request registers for each core
    reg        req_valid [0:NCORES-1];  // request is pending
    reg        req_we [0:NCORES-1];
    reg [31:0] req_addr [0:NCORES-1];
    reg [31:0] req_wdata [0:NCORES-1];

    // Round-robin state
    reg [$clog2(NCORES)-1:0] rr_ptr = 0;  // points to next core to serve
    wire [NCORES-1:0] req_valid_packed;

    wire [$clog2(NCORES)-1:0] sel_core;
    wire sel_valid;

    wire being_served [0:NCORES-1];

    wire                   we_int;
    wire [`VMEM_ADDRW-1:0] addr_int;
    wire             [2:0] wdata_int;

    always @(posedge clk_i) begin : reserve_requests_block
        for (j = 0; j < NCORES; j = j + 1) begin
            // Set valid if new request arrives
            if (!req_valid[j]) begin
                req_valid[j] <= addr[j] != 32'h0;  // new request
                req_we[j]    <= we[j];
                req_addr[j]  <= addr[j];
                req_wdata[j] <= wdata[j];
            end else if (being_served[j]) begin
                // Clear valid when being served
                req_valid[j] <= 1'b0;
                req_we[j]    <= 1'b0;
                req_addr[j]  <= 32'h0;
                req_wdata[j] <= 32'h0;
            end
        end
    end

    generate
        for (i = 0; i < NCORES; i = i + 1) begin : gen_output
            assign stall[i] = (addr[i] != 32'h0) // new request arrives
                            || (req_valid[i]); // pending request
        end
    endgenerate

    generate
        for (i = 0; i < NCORES; i = i + 1) begin : pack_req_inputs
            assign req_valid_packed[i] = req_valid[i];
        end
    endgenerate

    single_issue_arbiter arbiter (
        .rr_ptr_i    (rr_ptr),
        .req_valid_i (req_valid_packed),
        .valid_o     (sel_valid),
        .selector_o  (sel_core)
    );

    // Track which core is currently being served
    generate
        for (i = 0; i < NCORES; i = i + 1) begin : gen_being_served
            assign being_served[i] = sel_valid && sel_core == i;
        end
    endgenerate

    assign we_int    = sel_valid && req_we[sel_core];
    assign addr_int  = sel_valid ? req_addr[sel_core][`VMEM_ADDRW-1:0] : 16'h0;
    assign wdata_int = sel_valid ? req_wdata[sel_core][2:0] : 3'h0;

    // Update round-robin pointer
    always @(posedge clk_i) begin
        if (sel_valid) begin
            rr_ptr <= (sel_core + 1) % NCORES;
        end
    end

    vmem vmem (
        .clk_i   (clk_i),         // input  wire
        .we_i    (we_int),        // input  wire
        .waddr_i (addr_int),      // input  wire [`VMEM_ADDRW-1:0]
        .wdata_i (wdata_int),     // input  wire [2:0]
        .raddr_i (disp_raddr_i),  // input  wire [`VMEM_ADDRW-1:0]
        .rdata_o (disp_rdata_o)   // output wire [2:0]
    );
endmodule

`resetall
