`resetall
`default_nettype none

module comb_dbus_dmem #(
    parameter NCORES = `NCORES,
    parameter DMEM_ADDRW = `DMEM_ADDRW
) (
    input wire clk_i,
    input wire [NCORES-1:0] re_packed_i,
    input wire [NCORES-1:0] we_packed_i,
    input wire [DMEM_ADDRW*NCORES-1:0] addr_packed_i,
    input wire [32*NCORES-1:0] wdata_packed_i,
    input wire [4*NCORES-1:0] wstrb_packed_i,
    input wire [NCORES-1:0] is_lr_packed_i,
    input wire [NCORES-1:0] is_sc_packed_i,
    output wire [32*NCORES-1:0] rdata_packed_o,
    output wire [NCORES-1:0] stall_packed_o
);
    genvar i;
    integer j;
    integer k;

    localparam NCORES_A = NCORES / 2;           // Cores assigned to port A
    localparam NCORES_B = NCORES - NCORES_A;    // Cores assigned to port B
    localparam NCORES_A_W = (NCORES_A > 1) ? $clog2(NCORES_A) : 1;
    localparam NCORES_B_W = (NCORES_B > 1) ? $clog2(NCORES_B) : 1;

    // Unpack input arrays
    wire                  re   [0:NCORES-1];
    wire                  we   [0:NCORES-1];
    wire [DMEM_ADDRW-1:0] addr [0:NCORES-1];
    wire [31:0]           wdata[0:NCORES-1];
    wire [3:0]            wstrb[0:NCORES-1];
    wire                  is_lr[0:NCORES-1];
    wire                  is_sc[0:NCORES-1];
    reg  [31:0]           rdata[0:NCORES-1];
    reg                   stall[0:NCORES-1];

    generate
        for (i = 0; i < NCORES; i = i + 1) begin : unpack_arrays
            assign re[i]    = re_packed_i[i];
            assign we[i]    = we_packed_i[i];
            assign addr[i]  = addr_packed_i[DMEM_ADDRW*(i+1)-1:DMEM_ADDRW*i];
            assign wdata[i] = wdata_packed_i[32*(i+1)-1:32*i];
            assign wstrb[i] = wstrb_packed_i[4*(i+1)-1:4*i];
            assign is_lr[i] = is_lr_packed_i[i];
            assign is_sc[i] = is_sc_packed_i[i];
            assign rdata_packed_o[32*(i+1)-1:32*i] = rdata[i];
            assign stall_packed_o[i] = stall[i];
        end
    endgenerate

    // Round-robin pointers for port A and B
    reg [NCORES_A_W-1:0] rr_ptr_a_q = 0;
    reg [NCORES_B_W-1:0] rr_ptr_b_q = 0;

    // Port A: cores 0 to NCORES_A-1
    // Port B: cores NCORES_A to NCORES-1
    wire                  req_a [0:NCORES_A-1];  // request on port A
    wire                  req_b [0:NCORES_B-1];  // request on port B
    wire [DMEM_ADDRW-1:0] addr_a[0:NCORES_A-1];
    wire [DMEM_ADDRW-1:0] addr_b[0:NCORES_B-1];

    generate
        for (i = 0; i < NCORES_A; i = i + 1) begin : gen_req_a
            assign req_a[i] = re[i] | we[i];
            assign addr_a[i] = addr[i];
        end
        for (i = 0; i < NCORES_B; i = i + 1) begin : gen_req_b
            assign req_b[i] = re[NCORES_A + i] | we[NCORES_A + i];
            assign addr_b[i] = addr[NCORES_A + i];
        end
    endgenerate

    // Combinational arbitration for port A (round-robin)
    reg [NCORES_A_W-1:0] sel_a;
    reg valid_a;
    always @(*) begin
        sel_a = 0;
        valid_a = 1'b0;
        // Start from rr_ptr_a_q and search for first request
        for (j = 0; j < NCORES_A; j = j + 1) begin
            k = (rr_ptr_a_q + j) % NCORES_A;
            if (req_a[k] && !valid_a) begin
                sel_a = k;
                valid_a = 1'b1;
            end
        end
    end

    // Combinational arbitration for port B (round-robin)
    reg [NCORES_B_W-1:0] sel_b;
    reg valid_b;
    always @(*) begin
        sel_b = 0;
        valid_b = 1'b0;
        // Start from rr_ptr_b_q and search for first request
        for (j = 0; j < NCORES_B; j = j + 1) begin
            k = (rr_ptr_b_q + j) % NCORES_B;
            if (req_b[k] && !valid_b) begin
                sel_b = k;
                valid_b = 1'b1;
            end
        end
    end

    // LR/SC reservation registers for each core
    reg                  reservation_valid_q [0:NCORES-1];
    reg [DMEM_ADDRW-1:0] reservation_addr_q  [0:NCORES-1];

    reg                  reservation_valid_d [0:NCORES-1];
    reg [DMEM_ADDRW-1:0] reservation_addr_d  [0:NCORES-1];

    // Memory interface signals
    reg                  rea_int;
    reg                  reb_int;
    reg                  wea_int;
    reg                  web_int;
    reg [DMEM_ADDRW-1:0] addra_int;
    reg [DMEM_ADDRW-1:0] addrb_int;
    reg [31:0]           wdataa_int;
    reg [31:0]           wdatab_int;
    reg [3:0]            wstrba_int;
    reg [3:0]            wstrbb_int;

    wire [31:0] rdataa_dmem;
    wire [31:0] rdatab_dmem;

    // Registered read data from memory
    reg [31:0] rdataa_q;
    reg [31:0] rdatab_q;

    // Store which core to return data to
    reg [$clog2(NCORES)-1:0] ret_core_a_q;
    reg [$clog2(NCORES)-1:0] ret_core_b_q;
    reg ret_valid_a_q;
    reg ret_valid_b_q;
    reg ret_is_sc_a_q;
    reg ret_is_sc_b_q;
    reg sc_success_a_q;
    reg sc_success_b_q;

    // Combinational logic for memory access and stall generation
    always @(*) begin
        // Default values
        rea_int = 1'b0;
        reb_int = 1'b0;
        wea_int = 1'b0;
        web_int = 1'b0;
        addra_int = 0;
        addrb_int = 0;
        wdataa_int = 0;
        wdatab_int = 0;
        wstrba_int = 0;
        wstrbb_int = 0;

        // Setup reservation updates
        for (j = 0; j < NCORES; j = j + 1) begin
            reservation_valid_d[j] = reservation_valid_q[j];
            reservation_addr_d[j] = reservation_addr_q[j];
        end

        // Port A access
        if (valid_a) begin
            if (re[sel_a]) begin
                rea_int = 1'b1;
                addra_int = addr_a[sel_a];
                
                // Handle LR
                if (is_lr[sel_a]) begin
                    reservation_valid_d[sel_a] = 1'b1;
                    reservation_addr_d[sel_a] = addr_a[sel_a];
                end
            end else if (we[sel_a]) begin
                addra_int = addr_a[sel_a];
                
                // Handle SC
                if (is_sc[sel_a]) begin
                    // SC succeeds if reservation is valid and address matches
                    if (reservation_valid_q[sel_a] && reservation_addr_q[sel_a] == addr_a[sel_a]) begin
                        wea_int = 1'b1;
                        wdataa_int = wdata[sel_a];
                        wstrba_int = wstrb[sel_a];
                        // Invalidate all reservations for this address
                        for (j = 0; j < NCORES; j = j + 1) begin
                            if (reservation_valid_q[j] && reservation_addr_q[j] == addr_a[sel_a]) begin
                                reservation_valid_d[j] = 1'b0;
                            end
                        end
                    end
                end else begin
                    // Regular store
                    wea_int = 1'b1;
                    wdataa_int = wdata[sel_a];
                    wstrba_int = wstrb[sel_a];
                    // Invalidate reservations for this address
                    for (j = 0; j < NCORES; j = j + 1) begin
                        if (reservation_valid_q[j] && reservation_addr_q[j] == addr_a[sel_a]) begin
                            reservation_valid_d[j] = 1'b0;
                        end
                    end
                end
            end
        end

        // Port B access
        if (valid_b) begin
            if (re[NCORES_A + sel_b]) begin
                reb_int = 1'b1;
                addrb_int = addr_b[sel_b];
                
                // Handle LR
                if (is_lr[NCORES_A + sel_b]) begin
                    reservation_valid_d[NCORES_A + sel_b] = 1'b1;
                    reservation_addr_d[NCORES_A + sel_b] = addr_b[sel_b];
                end
            end else if (we[NCORES_A + sel_b]) begin
                addrb_int = addr_b[sel_b];
                
                // Handle SC
                if (is_sc[NCORES_A + sel_b]) begin
                    // SC succeeds if reservation is valid and address matches
                    if (reservation_valid_q[NCORES_A + sel_b] && reservation_addr_q[NCORES_A + sel_b] == addr_b[sel_b]) begin
                        web_int = 1'b1;
                        wdatab_int = wdata[NCORES_A + sel_b];
                        wstrbb_int = wstrb[NCORES_A + sel_b];
                        // Invalidate all reservations for this address
                        for (j = 0; j < NCORES; j = j + 1) begin
                            if (reservation_valid_q[j] && reservation_addr_q[j] == addr_b[sel_b]) begin
                                reservation_valid_d[j] = 1'b0;
                            end
                        end
                    end
                end else begin
                    // Regular store
                    web_int = 1'b1;
                    wdatab_int = wdata[NCORES_A + sel_b];
                    wstrbb_int = wstrb[NCORES_A + sel_b];
                    // Invalidate reservations for this address
                    for (j = 0; j < NCORES; j = j + 1) begin
                        if (reservation_valid_q[j] && reservation_addr_q[j] == addr_b[sel_b]) begin
                            reservation_valid_d[j] = 1'b0;
                        end
                    end
                end
            end
        end

        // Generate stall signals
        // Stall if there's a request from this core but it's not being served
        for (j = 0; j < NCORES_A; j = j + 1) begin
            stall[j] = req_a[j] && (!valid_a || sel_a != j);
        end
        for (j = 0; j < NCORES_B; j = j + 1) begin
            stall[NCORES_A + j] = req_b[j] && (!valid_b || sel_b != j);
        end

        // Output read data
        for (j = 0; j < NCORES; j = j + 1) begin
            if (ret_valid_a_q && ret_core_a_q == j) begin
                if (ret_is_sc_a_q) begin
                    rdata[j] = {31'b0, !sc_success_a_q};  // SC result: 0=success, 1=failure
                end else begin
                    rdata[j] = rdataa_q;
                end
            end else if (ret_valid_b_q && ret_core_b_q == j) begin
                if (ret_is_sc_b_q) begin
                    rdata[j] = {31'b0, !sc_success_b_q};  // SC result: 0=success, 1=failure
                end else begin
                    rdata[j] = rdatab_q;
                end
            end else begin
                rdata[j] = 32'h0;
            end
        end
    end

    // Sequential logic for round-robin pointers and memory read data
    reg [NCORES_A_W-1:0] rr_ptr_a_d;
    reg [NCORES_B_W-1:0] rr_ptr_b_d;
    reg [$clog2(NCORES)-1:0] ret_core_a_d;
    reg [$clog2(NCORES)-1:0] ret_core_b_d;
    reg ret_valid_a_d;
    reg ret_valid_b_d;
    reg ret_is_sc_a_d;
    reg ret_is_sc_b_d;
    reg sc_success_a_d;
    reg sc_success_b_d;

    always @(*) begin
        // Update round-robin pointers
        if (valid_a) begin
            rr_ptr_a_d = (sel_a + 1) % NCORES_A;
        end else begin
            rr_ptr_a_d = rr_ptr_a_q;
        end

        if (valid_b) begin
            rr_ptr_b_d = (sel_b + 1) % NCORES_B;
        end else begin
            rr_ptr_b_d = rr_ptr_b_q;
        end

        // Track return path for read data
        ret_valid_a_d = valid_a;
        ret_valid_b_d = valid_b;
        ret_core_a_d = sel_a;
        ret_core_b_d = NCORES_A + sel_b;
        ret_is_sc_a_d = valid_a && is_sc[sel_a];
        ret_is_sc_b_d = valid_b && is_sc[NCORES_A + sel_b];
        
        // SC success status
        sc_success_a_d = 1'b0;
        sc_success_b_d = 1'b0;
        if (valid_a && we[sel_a] && is_sc[sel_a]) begin
            sc_success_a_d = reservation_valid_q[sel_a] && (reservation_addr_q[sel_a] == addr_a[sel_a]);
        end
        if (valid_b && we[NCORES_A + sel_b] && is_sc[NCORES_A + sel_b]) begin
            sc_success_b_d = reservation_valid_q[NCORES_A + sel_b] && (reservation_addr_q[NCORES_A + sel_b] == addr_b[sel_b]);
        end
    end

    always @(posedge clk_i) begin
        rr_ptr_a_q <= rr_ptr_a_d;
        rr_ptr_b_q <= rr_ptr_b_d;
        rdataa_q <= rdataa_dmem;
        rdatab_q <= rdatab_dmem;
        ret_core_a_q <= ret_core_a_d;
        ret_core_b_q <= ret_core_b_d;
        ret_valid_a_q <= ret_valid_a_d;
        ret_valid_b_q <= ret_valid_b_d;
        ret_is_sc_a_q <= ret_is_sc_a_d;
        ret_is_sc_b_q <= ret_is_sc_b_d;
        sc_success_a_q <= sc_success_a_d;
        sc_success_b_q <= sc_success_b_d;

        for (j = 0; j < NCORES; j = j + 1) begin
            reservation_valid_q[j] <= reservation_valid_d[j];
            reservation_addr_q[j] <= reservation_addr_d[j];
        end
    end

    m_dmem dmem (
        .clk_i   (clk_i),            // input  wire
        .rea_i   (rea_int),          // input  wire
        .reb_i   (reb_int),          // input  wire
        .wea_i   (wea_int),          // input  wire
        .web_i   (web_int),          // input  wire
        .addra_i (addra_int),        // input  wire [ADDR_WIDTH-1:0]
        .addrb_i (addrb_int),        // input  wire [ADDR_WIDTH-1:0]
        .wdataa_i(wdataa_int),       // input  wire [DATA_WIDTH-1:0]
        .wdatab_i(wdatab_int),       // input  wire [DATA_WIDTH-1:0]
        .wstrba_i(wstrba_int),       // input  wire [STRB_WIDTH-1:0]
        .wstrbb_i(wstrbb_int),       // input  wire [STRB_WIDTH-1:0]
        .rdataa_o(rdataa_dmem),      // output wire [DATA_WIDTH-1:0]
        .rdatab_o(rdatab_dmem)       // output wire [DATA_WIDTH-1:0]
    );
endmodule

`resetall
