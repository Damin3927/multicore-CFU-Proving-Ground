`resetall
`default_nettype none

`include "config.vh"

module dbus_vmem #(
    parameter NCORES = `NCORES,
    parameter VMEM_ADDRW = `VMEM_ADDRW,
    parameter VMEM_WDATAW = 3
) (
    input wire clk_i,
    input wire [NCORES-1:0] we_packed_i,
    input wire [VMEM_ADDRW*NCORES-1:0] addr_packed_i,
    input wire [VMEM_WDATAW*NCORES-1:0] wdata_packed_i,
    output wire [NCORES-1:0] stall_packed_o,
    input wire [VMEM_ADDRW-1:0] disp_raddr_i,
    output wire [VMEM_WDATAW-1:0] disp_rdata_o
);
    genvar i;
    integer j;
    integer k;

    // Statemachine
    localparam IDLE = 'd0;
    localparam ACCESS = 'd1;
    localparam STATE_WIDTH = 'd2;

    reg [$clog2(STATE_WIDTH)-1:0] state_q = IDLE;
    reg [$clog2(STATE_WIDTH)-1:0] state_d;

    // Unpack input arrays
    wire                  we   [0:NCORES-1];
    wire [VMEM_ADDRW-1:0] addr [0:NCORES-1];
    wire [31:0]           wdata[0:NCORES-1];
    reg                   stall_q [0:NCORES-1];
    reg                   stall_d [0:NCORES-1];

    generate
        for (i = 0; i < NCORES; i = i + 1) begin : unpack_arrays
            assign we[i]    = we_packed_i[i];
            assign addr[i]  = addr_packed_i[VMEM_ADDRW*(i+1)-1:VMEM_ADDRW*i];
            assign wdata[i] = wdata_packed_i[VMEM_WDATAW*(i+1)-1:VMEM_WDATAW*i];
            assign stall_packed_o[i] = stall_q[i];
        end
    endgenerate

    // Reserved request registers for each core
    reg                   req_valid_q [0:NCORES-1];  // request is pending
    reg [VMEM_ADDRW-1:0]  req_addr_q  [0:NCORES-1];
    reg [VMEM_WDATAW-1:0] req_wdata_q [0:NCORES-1];

    reg                   req_valid_d [0:NCORES-1];
    reg [VMEM_ADDRW-1:0]  req_addr_d  [0:NCORES-1];
    reg [VMEM_WDATAW-1:0] req_wdata_d [0:NCORES-1];

    // Round-robin state
    reg [$clog2(NCORES)-1:0] rr_ptr_q = 0;  // points to next core to serve
    reg [$clog2(NCORES)-1:0] rr_ptr_d;

    // Selected core
    reg [$clog2(NCORES)-1:0] sel_core_q = 'd0;
    reg [$clog2(NCORES)-1:0] sel_core_d;
    reg [VMEM_ADDRW-1:0] sel_addr_q;
    reg [VMEM_ADDRW-1:0] sel_addr_d;

    wire [$clog2(NCORES)-1:0] sel_core_arb;
    wire sel_valid_arb;

    reg being_served [0:NCORES-1];

    reg we_int;
    reg [VMEM_ADDRW-1:0] addr_int;
    reg [VMEM_WDATAW-1:0] wdata_int;

    // Select cores in round-robin fashion
    wire [NCORES-1:0] req_valid_packed;
    generate
        for (i = 0; i < NCORES; i = i + 1) begin : pack_req_inputs
            assign req_valid_packed[i] = req_valid_q[i];
        end
    endgenerate

    single_issue_arbiter arbiter (
        .rr_ptr_i    (rr_ptr_q),
        .req_valid_i (req_valid_packed),
        .valid_o     (sel_valid_arb),
        .selector_o  (sel_core_arb)
    );

    wire select_fire;
    wire is_access;

    assign select_fire = (state_q == IDLE) && sel_valid_arb;
    assign is_access = (state_q == ACCESS);

    always @(*) begin
        state_d    = state_q;
        sel_core_d = sel_core_q;
        sel_addr_d = sel_addr_q;
        rr_ptr_d   = rr_ptr_q;
        we_int     = 1'b0;
        addr_int   = {VMEM_ADDRW{1'b0}};
        wdata_int  = {VMEM_WDATAW{1'b0}};

        for (k = 0; k < NCORES; k = k + 1) begin
            stall_d[k]      = we[k] || (req_valid_q[k]);
            req_valid_d[k]  = req_valid_q[k];
            req_addr_d[k]   = req_addr_q[k];
            req_wdata_d[k]  = req_wdata_q[k];
            being_served[k] = (is_access && sel_core_q == k);

            if (!req_valid_q[k]) begin
                req_valid_d[k]  = we[k];
                req_addr_d[k]   = addr[k];
                req_wdata_d[k]  = wdata[k];
            end else if (being_served[k]) begin
                req_valid_d[k]  = 1'b0;
            end
        end

        case (state_q)
            IDLE: begin
                if (select_fire) begin
                    state_d    = ACCESS;
                    sel_core_d = sel_core_arb;
                    sel_addr_d = req_addr_q[sel_core_arb];
                end
            end
            ACCESS: begin
                state_d    = IDLE;
                we_int     = 1'b1;
                addr_int   = sel_addr_q[VMEM_ADDRW-1:0];
                wdata_int  = req_wdata_q[sel_core_q];

                rr_ptr_d = (sel_core_q + 1) % NCORES;
            end
            default: begin
                state_d = IDLE;
            end
        endcase
    end

    always @(posedge clk_i) begin
        state_q     <= state_d;
        sel_core_q  <= sel_core_d;
        sel_addr_q  <= sel_addr_d;
        rr_ptr_q    <= rr_ptr_d;

        for (j = 0; j < NCORES; j = j + 1) begin
            stall_q[j]      <= stall_d[j];
            req_valid_q[j]  <= req_valid_d[j];
            req_addr_q[j]   <= req_addr_d[j];
            req_wdata_q[j]  <= req_wdata_d[j];
        end
    end

    vmem vmem (
        .clk_i   (clk_i),         // input  wire
        .we_i    (we_int),        // input  wire
        .waddr_i (addr_int),      // input  wire [VMEM_ADDRW-1:0]
        .wdata_i (wdata_int),     // input  wire [VMEM_WDATAW-1:0]
        .raddr_i (disp_raddr_i),  // input  wire [VMEM_ADDRW-1:0]
        .rdata_o (disp_rdata_o)   // output wire [VMEM_WDATAW-1:0]
    );
endmodule

`resetall
