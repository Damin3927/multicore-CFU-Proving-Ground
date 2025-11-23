`resetall
`default_nettype none

module dbus_dmem #(
    parameter NCORES = `NCORES
) (
    input wire clk_i,
    input wire [NCORES-1:0] re_packed_i,
    input wire [NCORES-1:0] we_packed_i,
    input wire [32*NCORES-1:0] addr_packed_i,
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
    integer m;

    // Statemachine
    localparam IDLE = 'd0;
    localparam RSVCHECK = 'd1;
    localparam ACCESS = 'd2;
    localparam STATE_WIDTH = 'd3;

    reg [$clog2(STATE_WIDTH)-1:0] state_a_q = IDLE;
    reg [$clog2(STATE_WIDTH)-1:0] state_a_d;
    reg [$clog2(STATE_WIDTH)-1:0] state_b_q = IDLE;
    reg [$clog2(STATE_WIDTH)-1:0] state_b_d;

    // Unpack input arrays
    wire        re   [0:NCORES-1];
    wire        we   [0:NCORES-1];
    wire [31:0] addr [0:NCORES-1];
    wire [31:0] wdata[0:NCORES-1];
    wire [3:0]  wstrb[0:NCORES-1];
    wire        is_lr[0:NCORES-1];
    wire        is_sc[0:NCORES-1];
    reg  [31:0] rdata_q [0:NCORES-1];
    reg         stall_q [0:NCORES-1];

    reg  [31:0] rdata_d [0:NCORES-1];
    reg         stall_d [0:NCORES-1];

    generate
        for (i = 0; i < NCORES; i = i + 1) begin : unpack_arrays
            assign re[i]    = re_packed_i[i];
            assign we[i]    = we_packed_i[i];
            assign addr[i]  = addr_packed_i[32*(i+1)-1:32*i];
            assign wdata[i] = wdata_packed_i[32*(i+1)-1:32*i];
            assign wstrb[i] = wstrb_packed_i[4*(i+1)-1:4*i];
            assign is_lr[i] = is_lr_packed_i[i];
            assign is_sc[i] = is_sc_packed_i[i];
            assign rdata_packed_o[32*(i+1)-1:32*i] = rdata_q[i];
            assign stall_packed_o[i] = stall_q[i];
        end
    endgenerate

    // Reserved request registers for each core
    reg        req_valid_q [0:NCORES-1];  // request is pending
    reg        req_re_q    [0:NCORES-1];
    reg        req_we_q    [0:NCORES-1];
    reg [31:0] req_addr_q  [0:NCORES-1];
    reg [31:0] req_wdata_q [0:NCORES-1];
    reg [3:0]  req_wstrb_q [0:NCORES-1];
    reg        req_is_lr_q [0:NCORES-1];
    reg        req_is_sc_q [0:NCORES-1];

    reg        req_valid_d [0:NCORES-1];
    reg        req_re_d    [0:NCORES-1];
    reg        req_we_d    [0:NCORES-1];
    reg [31:0] req_addr_d  [0:NCORES-1];
    reg [31:0] req_wdata_d [0:NCORES-1];
    reg [3:0]  req_wstrb_d [0:NCORES-1];
    reg        req_is_lr_d [0:NCORES-1];
    reg        req_is_sc_d [0:NCORES-1];

    // Round-robin state
    reg [$clog2(NCORES)-1:0] rr_ptr_q = 0;  // points to next core to serve

    // Select up to 2 cores to service this cycle
    reg [$clog2(NCORES)-1:0] sel_core_a_q = 'd0; // first selected core index
    reg [$clog2(NCORES)-1:0] sel_core_a_d;
    reg [$clog2(NCORES)-1:0] sel_core_b_q = 'd0; // second selected core index
    reg [$clog2(NCORES)-1:0] sel_core_b_d;
    wire [$clog2(NCORES)-1:0] sel_core_a_arb;
    wire [$clog2(NCORES)-1:0] sel_core_b_arb;
    wire sel_valid_a_arb;
    wire sel_valid_b_arb;

    reg being_served [0:NCORES-1];

    // LR/SC reservation
    reg        reservation_valid_q   [0:NCORES-1];
    reg [31:0] reservation_addr_q    [0:NCORES-1];
    reg        rsvcheck_sc_success_q [0:NCORES-1];

    reg        reservation_valid_d   [0:NCORES-1];
    reg [31:0] reservation_addr_d    [0:NCORES-1];
    reg        rsvcheck_sc_success_d [0:NCORES-1];

    reg rea_int;
    reg reb_int;
    reg wea_int;
    reg web_int;
    reg [31:0] addra_int;
    reg [31:0] addrb_int;
    reg [31:0] wdataa_int;
    reg [31:0] wdatab_int;
    reg [3:0]  wstrba_int;
    reg [3:0]  wstrbb_int;

    wire [31:0] rdataa_dmem;
    wire [31:0] rdatab_dmem;

    reg [$clog2(NCORES)-1:0] ret_core_a_q;
    reg [$clog2(NCORES)-1:0] ret_core_b_q;
    reg ret_valid_a_q;
    reg ret_valid_b_q;
    reg ret_is_sc_a_q;
    reg ret_is_sc_b_q;

    reg [$clog2(NCORES)-1:0] ret_core_a_d;
    reg [$clog2(NCORES)-1:0] ret_core_b_d;
    reg ret_valid_a_d;
    reg ret_valid_b_d;
    reg ret_is_sc_a_d;
    reg ret_is_sc_b_d;

    reg [$clog2(NCORES)-1:0] rr_ptr_d;

    // Select cores in round-robin fashion
    wire [NCORES-1:0] req_valid_packed;
    wire [NCORES*32-1:0] req_addr_packed;
    generate
        for (i = 0; i < NCORES; i = i + 1) begin : pack_req_inputs
            assign req_valid_packed[i] = req_valid_q[i];
            assign req_addr_packed[32*(i+1)-1:32*i] = req_addr_q[i];
        end
    endgenerate

    dual_issue_arbiter arbiter (
        .rr_ptr_i         (rr_ptr_q),
        .req_valid_i      (req_valid_packed),
        .req_addr_packed_i(req_addr_packed),
        .valid_a_o        (sel_valid_a_arb),
        .valid_b_o        (sel_valid_b_arb),
        .selector_a_o     (sel_core_a_arb),
        .selector_b_o     (sel_core_b_arb)
    );

    wire select_a_fire;
    wire select_b_fire;
    wire is_access_a;
    wire is_access_b;

    assign select_a_fire = (state_a_q == IDLE) && sel_valid_a_arb;
    assign select_b_fire = (state_b_q == IDLE) && sel_valid_b_arb
                        && ((state_a_q == IDLE) || (sel_core_b_arb != sel_core_a_q))
                        && (!select_a_fire || (sel_core_b_arb != sel_core_a_arb));
    assign is_access_a = (state_a_q == ACCESS);
    assign is_access_b = (state_b_q == ACCESS);

    always @(*) begin
        state_a_d       = state_a_q;
        sel_core_a_d    = sel_core_a_q;
        state_b_d       = state_b_q;
        sel_core_b_d    = sel_core_b_q;
        rr_ptr_d        = rr_ptr_q;
        ret_valid_a_d  = ret_valid_a_q;
        ret_valid_b_d  = ret_valid_b_q;
        ret_core_a_d   = ret_core_a_q;
        ret_core_b_d   = ret_core_b_q;
        ret_is_sc_a_d  = ret_is_sc_a_q;
        ret_is_sc_b_d  = ret_is_sc_b_q;
        rea_int         = 1'b0;
        reb_int         = 1'b0;
        wea_int         = 1'b0;
        web_int         = 1'b0;
        addra_int       = 32'h0;
        addrb_int       = 32'h0;
        wdataa_int      = 32'h0;
        wdatab_int      = 32'h0;
        wstrba_int      = 4'h0;
        wstrbb_int      = 4'h0;

        for (k = 0; k < NCORES; k = k + 1) begin
            stall_d[k]               = (addr[k] != 32'h0) // new request arrives
                                       || (req_valid_q[k]); // pending request
            rdata_d[k]               = (ret_valid_a_q && ret_core_a_q == k) ? (ret_is_sc_a_q ? {31'b0, !rsvcheck_sc_success_q[k]} : rdataa_dmem) :
                                       (ret_valid_b_q && ret_core_b_q == k) ? (ret_is_sc_b_q ? {31'b0, !rsvcheck_sc_success_q[k]} : rdatab_dmem) : 32'h0;
            req_valid_d[k]           = req_valid_q[k];
            req_re_d[k]              = req_re_q[k];
            req_we_d[k]              = req_we_q[k];
            req_addr_d[k]            = req_addr_q[k];
            req_wdata_d[k]           = req_wdata_q[k];
            req_wstrb_d[k]           = req_wstrb_q[k];
            req_is_lr_d[k]           = req_is_lr_q[k];
            req_is_sc_d[k]           = req_is_sc_q[k];
            reservation_valid_d[k]   = reservation_valid_q[k];
            reservation_addr_d[k]    = reservation_addr_q[k];
            rsvcheck_sc_success_d[k] = rsvcheck_sc_success_q[k];
            being_served[k]          = (is_access_a && sel_core_a_q == k)
                                       || (is_access_b && sel_core_b_q == k);

            if (!req_valid_q[k]) begin
                req_valid_d[k] = (addr[k] != 32'h0);
                req_re_d[k]    = re[k];
                req_we_d[k]    = we[k];
                req_addr_d[k]  = addr[k];
                req_wdata_d[k] = wdata[k];
                req_wstrb_d[k] = wstrb[k];
                req_is_lr_d[k] = is_lr[k];
                req_is_sc_d[k] = is_sc[k];
            end else if (being_served[k]) begin
                req_valid_d[k] = 1'b0;
                req_re_d[k]    = 1'b0;
                req_we_d[k]    = 1'b0;
                req_addr_d[k]  = 32'h0;
                req_wdata_d[k] = 32'h0;
                req_wstrb_d[k] = 4'h0;
                req_is_lr_d[k] = 1'b0;
                req_is_sc_d[k] = 1'b0;
            end
        end

        case (state_a_q)
            IDLE: begin
                if (select_a_fire) begin
                    if (req_re_q[sel_core_a_arb] && !req_is_lr_q[sel_core_a_arb]) begin // simple load
                        state_a_d = ACCESS;
                    end else begin
                        state_a_d = RSVCHECK;
                    end
                    sel_core_a_d = sel_core_a_arb;
                end

                if (ret_valid_a_q) begin
                    rsvcheck_sc_success_d[ret_core_a_q] = 1'b0;
                    ret_valid_a_d = 1'b0;
                end
            end
            RSVCHECK: begin
                state_a_d = ACCESS;
                if (req_re_q[sel_core_a_q] && req_is_lr_q[sel_core_a_q]) begin
                    reservation_valid_d[sel_core_a_q] = 1'b1;
                    reservation_addr_d[sel_core_a_q]  = req_addr_q[sel_core_a_q];
                end else if (req_we_q[sel_core_a_q] && req_is_sc_q[sel_core_a_q]) begin
                    rsvcheck_sc_success_d[sel_core_a_q] = reservation_valid_q[sel_core_a_q] && (reservation_addr_q[sel_core_a_q] == req_addr_q[sel_core_a_q]);
                    if (rsvcheck_sc_success_d[sel_core_a_q]) begin
                        for (m = 0; m < NCORES; m = m + 1) begin
                            if (reservation_valid_q[m] && reservation_addr_q[m] == req_addr_q[sel_core_a_q]) begin
                                reservation_valid_d[m] = 1'b0;
                            end
                        end
                    end
                end else if (req_we_q[sel_core_a_q] && !req_is_sc_q[sel_core_a_q]) begin
                    for (m = 0; m < NCORES; m = m + 1) begin
                        if (reservation_valid_q[m] && reservation_addr_q[m] == req_addr_q[sel_core_a_q]) begin
                            reservation_valid_d[m] = 1'b0;
                        end
                    end
                end
            end
            ACCESS: begin
                state_a_d      = IDLE;
                ret_valid_a_d  = 1'b1;
                ret_core_a_d   = sel_core_a_q;
                ret_is_sc_a_d  = req_is_sc_q[sel_core_a_q];
                rea_int        = req_re_q[sel_core_a_q];
                wea_int        = req_we_q[sel_core_a_q] && (req_is_sc_q[sel_core_a_q] ? rsvcheck_sc_success_q[sel_core_a_q] : 1'b1);
                addra_int      = req_addr_q[sel_core_a_q];
                wdataa_int     = req_wdata_q[sel_core_a_q];
                wstrba_int     = req_wstrb_q[sel_core_a_q];
            end
            default: begin
                state_a_d = IDLE;
            end
        endcase

        case (state_b_q)
            IDLE: begin
                if (select_b_fire) begin
                    if (req_re_q[sel_core_b_arb] && !req_is_lr_q[sel_core_b_arb]) begin // simple load
                        state_b_d = ACCESS;
                    end else begin
                        state_b_d = RSVCHECK;
                    end
                    sel_core_b_d = sel_core_b_arb;
                end

                if (ret_valid_b_q) begin
                    rsvcheck_sc_success_d[ret_core_b_q] = 1'b0;
                    ret_valid_b_d = 1'b0;
                end
            end
            RSVCHECK: begin
                state_b_d = ACCESS;
                if (req_re_q[sel_core_b_q] && req_is_lr_q[sel_core_b_q]) begin
                    reservation_valid_d[sel_core_b_q] = 1'b1;
                    reservation_addr_d[sel_core_b_q]  = req_addr_q[sel_core_b_q];
                end else if (req_we_q[sel_core_b_q] && req_is_sc_q[sel_core_b_q]) begin
                    rsvcheck_sc_success_d[sel_core_b_q] = reservation_valid_q[sel_core_b_q] && (reservation_addr_q[sel_core_b_q] == req_addr_q[sel_core_b_q]);
                    if (rsvcheck_sc_success_d[sel_core_b_q]) begin
                        for (m = 0; m < NCORES; m = m + 1) begin
                            if (reservation_valid_q[m] && reservation_addr_q[m] == req_addr_q[sel_core_b_q]) begin
                                reservation_valid_d[m] = 1'b0;
                            end
                        end
                    end
                end else if (req_we_q[sel_core_b_q] && !req_is_sc_q[sel_core_b_q]) begin
                    for (m = 0; m < NCORES; m = m + 1) begin
                        if (reservation_valid_q[m] && reservation_addr_q[m] == req_addr_q[sel_core_b_q]) begin
                            reservation_valid_d[m] = 1'b0;
                        end
                    end
                end
            end
            ACCESS: begin
                state_b_d      = IDLE;
                ret_valid_b_d  = 1'b1;
                ret_core_b_d   = sel_core_b_q;
                ret_is_sc_b_d  = req_is_sc_q[sel_core_b_q];
                reb_int        = req_re_q[sel_core_b_q];
                web_int        = req_we_q[sel_core_b_q] && (req_is_sc_q[sel_core_b_q] ? rsvcheck_sc_success_q[sel_core_b_q] : 1'b1);
                addrb_int      = req_addr_q[sel_core_b_q];
                wdatab_int     = req_wdata_q[sel_core_b_q];
                wstrbb_int     = req_wstrb_q[sel_core_b_q];
            end
            default: begin
                state_b_d = IDLE;
            end
        endcase

        if (is_access_a && is_access_b) begin
            rr_ptr_d = (sel_core_b_q + 1) % NCORES;
        end else if (is_access_a) begin
            rr_ptr_d = (sel_core_a_q + 1) % NCORES;
        end
    end

    always @(posedge clk_i) begin
        state_a_q    <= state_a_d;
        state_b_q    <= state_b_d;
        sel_core_a_q <= sel_core_a_d;
        sel_core_b_q <= sel_core_b_d;
        rr_ptr_q       <= rr_ptr_d;
        ret_valid_a_q <= ret_valid_a_d;
        ret_valid_b_q <= ret_valid_b_d;
        ret_core_a_q  <= ret_core_a_d;
        ret_core_b_q  <= ret_core_b_d;
        ret_is_sc_a_q <= ret_is_sc_a_d;
        ret_is_sc_b_q <= ret_is_sc_b_d;

        for (j = 0; j < NCORES; j = j + 1) begin
            stall_q[j]             <= stall_d[j];
            rdata_q[j]             <= rdata_d[j];
            req_valid_q[j]         <= req_valid_d[j];
            req_re_q[j]            <= req_re_d[j];
            req_we_q[j]            <= req_we_d[j];
            req_addr_q[j]          <= req_addr_d[j];
            req_wdata_q[j]         <= req_wdata_d[j];
            req_wstrb_q[j]         <= req_wstrb_d[j];
            req_is_lr_q[j]         <= req_is_lr_d[j];
            req_is_sc_q[j]         <= req_is_sc_d[j];
            reservation_valid_q[j] <= reservation_valid_d[j];
            reservation_addr_q[j]  <= reservation_addr_d[j];
            rsvcheck_sc_success_q[j] <= rsvcheck_sc_success_d[j];
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
