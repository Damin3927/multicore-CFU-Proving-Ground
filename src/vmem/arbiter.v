`resetall
`default_nettype none

module single_issue_arbiter #(
    parameter NCORES = `NCORES,
    parameter ADDR_WIDTH = 32
) (
    input wire [$clog2(NCORES)-1:0] rr_ptr_i,
    input wire         [NCORES-1:0] req_valid_i,
    output reg                      valid_o,
    output reg [$clog2(NCORES)-1:0] selector_o
);
    integer j;

    wire [2*NCORES-1:0] req_double = {req_valid_i, req_valid_i};
    wire [2*NCORES-1:0] req_rotated = req_double >> rr_ptr_i;

    // Find Candidate
    wire [2*NCORES-1:0] gnt_rotated = req_rotated & ~(req_rotated - 1);

    // De-rotate
    wire [2*NCORES-1:0] gnt_double = gnt_rotated << rr_ptr_i;
    wire [NCORES-1:0] gnt_onehot = gnt_double[NCORES-1:0] | gnt_double[2*NCORES-1:NCORES];

    // Encode (one-hot to binary)
    always @(*) begin
        selector_o = 0;
        for (j = 0; j < NCORES; j = j + 1) begin
            if (gnt_onehot[j]) selector_o = j[$clog2(NCORES)-1:0];
        end

        valid_o = |gnt_onehot;
    end
endmodule

`resetall
