`resetall
`default_nettype none

module dual_issue_arbiter #(
    parameter NCORES = `NCORES,
    parameter ADDR_WIDTH = 32
) (
    input wire    [$clog2(NCORES)-1:0] rr_ptr_i,
    input wire            [NCORES-1:0] req_valid_i,
    input wire [NCORES*ADDR_WIDTH-1:0] req_addr_packed_i,
    output reg                         valid_a_o,
    output reg                         valid_b_o,
    output reg    [$clog2(NCORES)-1:0] selector_a_o,
    output reg    [$clog2(NCORES)-1:0] selector_b_o
);
    wire [ADDR_WIDTH-1:0] req_addr [0:NCORES-1];
    genvar i;
    integer j;

    generate
        for (i = 0; i < NCORES; i = i + 1) begin : unpack_req_addr
            assign req_addr[i] = req_addr_packed_i[ADDR_WIDTH*(i+1)-1:ADDR_WIDTH*i];
        end
    endgenerate

    wire [2*NCORES-1:0] req_double = {req_valid_i, req_valid_i};
    wire [2*NCORES-1:0] req_rotated = req_double >> rr_ptr_i;

    // Find Candidate A
    wire [2*NCORES-1:0] gnt_rotated_a = req_rotated & ~(req_rotated - 1);

    // Find Candidate B
    wire [2*NCORES-1:0] req_rotated_masked = req_rotated & ~gnt_rotated_a;
    wire [2*NCORES-1:0] gnt_rotated_b      = req_rotated_masked & ~(req_rotated_masked - 1);

    // De-rotate
    wire [2*NCORES-1:0] gnt_double_a = gnt_rotated_a << rr_ptr_i;
    wire [2*NCORES-1:0] gnt_double_b = gnt_rotated_b << rr_ptr_i;
    wire [NCORES-1:0] gnt_onehot_a = gnt_double_a[NCORES-1:0] | gnt_double_a[2*NCORES-1:NCORES];
    wire [NCORES-1:0] gnt_onehot_b = gnt_double_b[NCORES-1:0] | gnt_double_b[2*NCORES-1:NCORES];


    // Encode (one-hot to binary)
    always @(*) begin
        selector_a_o = 0;
        selector_b_o = 0;
        for (j = 0; j < NCORES; j = j + 1) begin
            if (gnt_onehot_a[j]) selector_a_o = j[$clog2(NCORES)-1:0];
            if (gnt_onehot_b[j]) selector_b_o = j[$clog2(NCORES)-1:0];
        end
    end

    // final validation
    always @(*) begin
        valid_a_o = |gnt_onehot_a;
        if (|gnt_onehot_b &&
            (req_addr[selector_a_o][ADDR_WIDTH-1:2] != req_addr[selector_b_o][ADDR_WIDTH-1:2])
        ) begin
            valid_b_o = 1'b1;
        end else begin
            valid_b_o = 1'b0;
        end
    end
endmodule

`resetall
