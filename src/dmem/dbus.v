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
    // Round-robin arbiter for multi-core dmem access
    genvar i;
    integer j, k, m;

    // Unpack input arrays
    wire        re   [0:NCORES-1];
    wire        we   [0:NCORES-1];
    wire [31:0] addr [0:NCORES-1];
    wire [31:0] wdata[0:NCORES-1];
    wire [3:0]  wstrb[0:NCORES-1];
    wire        is_lr[0:NCORES-1];
    wire        is_sc[0:NCORES-1];
    wire [31:0] rdata[0:NCORES-1];
    wire        stall[0:NCORES-1];
    reg  [31:0] rdata_reg [0:NCORES-1];
    reg         stall_o   [0:NCORES-1];

    generate
        for (i = 0; i < NCORES; i = i + 1) begin : unpack_arrays
            assign re[i]    = re_packed_i[i];
            assign we[i]    = we_packed_i[i];
            assign addr[i]  = addr_packed_i[32*(i+1)-1:32*i];
            assign wdata[i] = wdata_packed_i[32*(i+1)-1:32*i];
            assign wstrb[i] = wstrb_packed_i[4*(i+1)-1:4*i];
            assign is_lr[i] = is_lr_packed_i[i];
            assign is_sc[i] = is_sc_packed_i[i];
            assign rdata_packed_o[32*(i+1)-1:32*i] = rdata_reg[i];
            assign stall_packed_o[i] = stall_o[i];
        end
    endgenerate

    always @(posedge clk_i) begin
        for (j = 0; j < NCORES; j = j + 1) begin
            stall_o[j] <= stall[j];
        end
    end

    // Reserved request registers for each core
    reg        req_valid [0:NCORES-1];  // request is pending
    reg        req_re [0:NCORES-1];
    reg        req_we [0:NCORES-1];
    reg [31:0] req_addr [0:NCORES-1];
    reg [31:0] req_wdata [0:NCORES-1];
    reg [3:0]  req_wstrb [0:NCORES-1];
    reg        req_is_lr [0:NCORES-1];
    reg        req_is_sc [0:NCORES-1];

    // Round-robin state
    reg [$clog2(NCORES)-1:0] rr_ptr = 0;  // points to next core to serve

    // Select up to 2 cores to service this cycle
    reg [$clog2(NCORES)-1:0] sel_core_a; // first selected core index
    reg [$clog2(NCORES)-1:0] sel_core_b; // second selected core index
    wire [$clog2(NCORES)-1:0] sel_core_a_logic;
    wire [$clog2(NCORES)-1:0] sel_core_b_logic;
    reg sel_valid_a;                     // if a port is selected or not
    reg sel_valid_b;                     // if b port is selected or not
    wire sel_valid_a_logic;
    wire sel_valid_b_logic;

    wire being_served [0:NCORES-1];

    reg rsvcheck_valid_a;
    reg rsvcheck_valid_b;

    // LR/SC reservation
    reg        reservation_valid   [0:NCORES-1];
    reg [31:0] reservation_addr    [0:NCORES-1];
    reg        rsvcheck_sc_success [0:NCORES-1];

    wire sc_success_a;
    wire sc_success_b;

    wire rea_int;
    wire reb_int;
    wire wea_int;
    wire web_int;
    wire [31:0] addra_int;
    wire [31:0] addrb_int;
    wire [31:0] wdataa_int;
    wire [31:0] wdatab_int;
    wire [3:0]  wstrba_int;
    wire [3:0]  wstrbb_int;
    wire is_sc_a;
    wire is_sc_b;

    wire [31:0] rdataa_dmem;
    wire [31:0] rdatab_dmem;

    reg [$clog2(NCORES)-1:0] resp_core_a;
    reg [$clog2(NCORES)-1:0] resp_core_b;
    reg resp_valid_a;
    reg resp_valid_b;
    reg resp_is_sc_a;
    reg resp_is_sc_b;

    // Reserve incoming requests
    always @(posedge clk_i) begin : reserve_requests_block
        for (j = 0; j < NCORES; j = j + 1) begin
            // Set valid if new request arrives
            if (!req_valid[j]) begin
                req_valid[j] <= addr[j] != 32'h0;  // new request
                req_re[j]    <= re[j];
                req_we[j]    <= we[j];
                req_addr[j]  <= addr[j];
                req_wdata[j] <= wdata[j];
                req_wstrb[j] <= wstrb[j];
                req_is_lr[j] <= is_lr[j];
                req_is_sc[j] <= is_sc[j];
            end else if (being_served[j]) begin
                // Clear valid when being served
                req_valid[j] <= 1'b0;
                req_re[j]    <= 1'b0;
                req_we[j]    <= 1'b0;
                req_addr[j]  <= 32'h0;
                req_wdata[j] <= 32'h0;
                req_wstrb[j] <= 4'h0;
                req_is_lr[j] <= 1'b0;
                req_is_sc[j] <= 1'b0;
            end
        end
    end

    generate
        for (i = 0; i < NCORES; i = i + 1) begin : gen_output
            assign stall[i] = (addr[i] != 0) // new request arrives
                            || (req_valid[i]); // pending request
            assign rdata[i] = (resp_valid_a && resp_core_a == i) ? (resp_is_sc_a ? {31'b0, !rsvcheck_sc_success[i]} : rdataa_dmem) :
                              (resp_valid_b && resp_core_b == i) ? (resp_is_sc_b ? {31'b0, !rsvcheck_sc_success[i]} : rdatab_dmem) : 32'h0;
        end
    endgenerate

    always @(posedge clk_i) begin
        for (j = 0; j < NCORES; j = j + 1) begin
            rdata_reg[j] <= rdata[j];
        end
    end

    // Select cores in round-robin fashion
    wire [NCORES-1:0] req_valid_packed;
    wire [NCORES*32-1:0] req_addr_packed;
    generate
        for (i = 0; i < NCORES; i = i + 1) begin : pack_req_inputs
            assign req_valid_packed[i] = req_valid[i];
            assign req_addr_packed[32*(i+1)-1:32*i] = req_addr[i];
        end
    endgenerate

    dual_issue_arbiter arbiter (
        .rr_ptr_i         (rr_ptr),
        .req_valid_i      (req_valid_packed),
        .req_addr_packed_i(req_addr_packed),
        .valid_a_o        (sel_valid_a_logic),
        .valid_b_o        (sel_valid_b_logic),
        .selector_a_o     (sel_core_a_logic),
        .selector_b_o     (sel_core_b_logic)
    );

    always @(posedge clk_i) begin
        if (sel_valid_a || rsvcheck_valid_a) begin
            sel_valid_a <= 1'b0;
        end else begin
            sel_valid_a <= sel_valid_a_logic;
            sel_core_a <= sel_core_a_logic;
        end

        if (sel_valid_b || rsvcheck_valid_b) begin
            sel_valid_b <= 1'b0;
        end else if (sel_core_b_logic != sel_core_a) begin
            sel_valid_b <= sel_valid_b_logic;
            sel_core_b <= sel_core_b_logic;
        end
    end

    generate
        for (i = 0; i < NCORES; i = i + 1) begin : gen_being_served
            assign being_served[i] = (rsvcheck_valid_a && sel_core_a == i)
                                  || (rsvcheck_valid_b && sel_core_b == i);
        end
    endgenerate

    always @(posedge clk_i) begin
        if (rsvcheck_valid_a) begin
            rsvcheck_valid_a <= 1'b0;
        end else begin
            rsvcheck_valid_a <= sel_valid_a;
        end

        if (rsvcheck_valid_b) begin
            rsvcheck_valid_b <= 1'b0;
        end else begin
            rsvcheck_valid_b <= sel_valid_b;
        end
    end

    assign sc_success_a = reservation_valid[sel_core_a] && (reservation_addr[sel_core_a] == req_addr[sel_core_a]);
    assign sc_success_b = reservation_valid[sel_core_b] && (reservation_addr[sel_core_b] == req_addr[sel_core_b]);

    always @(posedge clk_i) begin
        // sel_core_a request handling
        if (sel_valid_a) begin
            if (req_re[sel_core_a] && req_is_lr[sel_core_a]) begin
                // set addr to the reservation set
                reservation_valid[sel_core_a] <= 1'b1;
                reservation_addr[sel_core_a]  <= req_addr[sel_core_a];
            end else if (req_we[sel_core_a] && req_is_sc[sel_core_a]) begin
                rsvcheck_sc_success[sel_core_a] <= sc_success_a;
                if (sc_success_a) begin
                    // clear reservation on successful SC
                    for (j = 0; j < NCORES; j = j + 1) begin
                        if (reservation_valid[j] && reservation_addr[j] == req_addr[sel_core_a]) begin
                            reservation_valid[j] <= 1'b0;
                            reservation_addr[j]  <= 32'h0;
                        end
                    end
                end
            end else if (req_we[sel_core_a] && !req_is_sc[sel_core_a]) begin
                // clear reservation if store to the same addr in one of the reservation set
                for (j = 0; j < NCORES; j = j + 1) begin
                    if (reservation_valid[j] && reservation_addr[j] == req_addr[sel_core_a]) begin
                        reservation_valid[j] <= 1'b0;
                        reservation_addr[j]  <= 32'h0;
                    end
                end
            end
        end

        // sel_core_b request handling
        if (sel_valid_b) begin
            if (req_re[sel_core_b] && req_is_lr[sel_core_b]) begin
                // set addr to the reservation set
                reservation_valid[sel_core_b] <= 1'b1;
                reservation_addr[sel_core_b]  <= req_addr[sel_core_b];
            end else if (req_we[sel_core_b] && req_is_sc[sel_core_b]) begin
                rsvcheck_sc_success[sel_core_b] <= sc_success_b;
                if (sc_success_b) begin
                    // clear reservation on successful SC
                    for (j = 0; j < NCORES; j = j + 1) begin
                        if (reservation_valid[j] && reservation_addr[j] == req_addr[sel_core_b]) begin
                            reservation_valid[j] <= 1'b0;
                            reservation_addr[j]  <= 32'h0;
                        end
                    end
                end
            end else if (req_we[sel_core_b] && !req_is_sc[sel_core_b]) begin
                // clear reservation if store to the same addr in one of the reservation set
                for (j = 0; j < NCORES; j = j + 1) begin
                    if (reservation_valid[j] && reservation_addr[j] == req_addr[sel_core_b]) begin
                        reservation_valid[j] <= 1'b0;
                        reservation_addr[j]  <= 32'h0;
                    end
                end
            end
        end
    end

    assign rea_int    = rsvcheck_valid_a && req_re[sel_core_a];
    assign reb_int    = rsvcheck_valid_b && req_re[sel_core_b];
    assign wea_int    = rsvcheck_valid_a && req_we[sel_core_a] && (req_is_sc[sel_core_a] ? rsvcheck_sc_success[sel_core_a] : 1'b1);
    assign web_int    = rsvcheck_valid_b && req_we[sel_core_b] && (req_is_sc[sel_core_b] ? rsvcheck_sc_success[sel_core_b] : 1'b1);
    assign addra_int  = rsvcheck_valid_a ? req_addr[sel_core_a]  : 0;
    assign addrb_int  = rsvcheck_valid_b ? req_addr[sel_core_b]  : 0;
    assign wdataa_int = rsvcheck_valid_a ? req_wdata[sel_core_a] : 0;
    assign wdatab_int = rsvcheck_valid_b ? req_wdata[sel_core_b] : 0;
    assign wstrba_int = rsvcheck_valid_a ? req_wstrb[sel_core_a] : 0;
    assign wstrbb_int = rsvcheck_valid_b ? req_wstrb[sel_core_b] : 0;
    assign is_sc_a    = rsvcheck_valid_a && req_is_sc[sel_core_a];
    assign is_sc_b    = rsvcheck_valid_b && req_is_sc[sel_core_b];

    always @(posedge clk_i) begin
        resp_core_a  <= sel_core_a;
        resp_core_b  <= sel_core_b;
        resp_valid_a <= rsvcheck_valid_a;
        resp_valid_b <= rsvcheck_valid_b;
        resp_is_sc_a <= is_sc_a;
        resp_is_sc_b <= is_sc_b;

        if (resp_valid_a && rsvcheck_sc_success[resp_core_a]) begin
            rsvcheck_sc_success[resp_core_a] <= 1'b0;
        end
        if (resp_valid_b && rsvcheck_sc_success[resp_core_b]) begin
            rsvcheck_sc_success[resp_core_b] <= 1'b0;
        end
    end

    // Update round-robin pointer
    always @(posedge clk_i) begin
        if (sel_valid_a && sel_valid_b) begin
            rr_ptr <= (sel_core_b + 1) % NCORES;
        end else if (sel_valid_a) begin
            rr_ptr <= (sel_core_a + 1) % NCORES;
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
