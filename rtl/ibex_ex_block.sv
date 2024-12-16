// Copyright lowRISC contributors.
// Copyright 2018 ETH Zurich and University of Bologna, see also CREDITS.md.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

/**
 * Execution stage
 *
 * Execution block: Hosts ALU and MUL/DIV unit
 */
module ibex_ex_block #(
  parameter ibex_pkg::rv32m_e RV32M           = ibex_pkg::RV32MFast,
  parameter ibex_pkg::rv32b_e RV32B           = ibex_pkg::RV32BNone,
  parameter bit               BranchTargetALU = 0
) (
  input  logic                  clk_i,
  input  logic                  rst_ni,

  // ALU
  input  ibex_pkg::alu_op_e     alu_operator_i,
  input  logic [7:0]           instr_rdata_ex_i,
  input  logic [31:0]           alu_operand_a_i,
  input  logic [31:0]           alu_operand_b_i,
  input  logic                  alu_instr_first_cycle_i,

  // Branch Target ALU
  // All of these signals are unusued when BranchTargetALU == 0
  input  logic [31:0]           bt_a_operand_i,
  input  logic [31:0]           bt_b_operand_i,

  // Multiplier/Divider
  input  ibex_pkg::md_op_e      multdiv_operator_i,
  input  logic                  mult_en_i,             // dynamic enable signal, for FSM control
  input  logic                  div_en_i,              // dynamic enable signal, for FSM control
  input  logic                  mult_sel_i,            // static decoder output, for data muxes
  input  logic                  div_sel_i,             // static decoder output, for data muxes
  input  logic  [1:0]           multdiv_signed_mode_i,
  input  logic [31:0]           multdiv_operand_a_i,
  input  logic [31:0]           multdiv_operand_b_i,
  input  logic                  multdiv_ready_id_i,
  input  logic                  data_ind_timing_i,

  // intermediate val reg
  output logic [1:0]            imd_val_we_o,
  output logic [33:0]           imd_val_d_o[2],
  input  logic [33:0]           imd_val_q_i[2],

  // Outputs
  output logic [31:0]           alu_adder_result_ex_o, // to LSU
  output logic [31:0]           result_ex_o,
  output logic [31:0]           branch_target_o,       // to IF
  output logic                  branch_decision_o,     // to ID

  output logic                  ex_valid_o,             // EX has valid output

  // BTB update ports
  output logic        btb_data_write_o,
  output logic [7:0]  btb_data_addr_o,
  output logic [1:0]  btb_data_wdata_o,
  input  logic [1:0]  btb_data_rdata_i
  // input  logic [7:0]  instr_rdata_ex_i

);



  import ibex_pkg::*;

  logic [31:0] alu_result, multdiv_result;
  logic [31:0] alu_adder_result_ex_o_raw;
  logic [31:0] alu_result_raw;

  logic [32:0] multdiv_alu_operand_b, multdiv_alu_operand_a;
  logic [33:0] alu_adder_result_ext;
  logic        alu_cmp_result, alu_is_equal_result;
  logic        multdiv_valid;
  logic        multdiv_sel;
  logic [31:0] alu_imd_val_q[2];
  logic [31:0] alu_imd_val_d[2];
  logic [ 1:0] alu_imd_val_we;
  logic [33:0] multdiv_imd_val_d[2];
  logic [ 1:0] multdiv_imd_val_we;

  /*
    The multdiv_i output is never selected if RV32M=RV32MNone
    At synthesis time, all the combinational and sequential logic
    from the multdiv_i module are eliminated
  */
  if (RV32M != RV32MNone) begin : gen_multdiv_m
    assign multdiv_sel = mult_sel_i | div_sel_i;
  end else begin : gen_multdiv_no_m
    assign multdiv_sel = 1'b0;
  end

  // Intermediate Value Register Mux
  assign imd_val_d_o[0] = multdiv_sel ? multdiv_imd_val_d[0] : {2'b0, alu_imd_val_d[0]};
  assign imd_val_d_o[1] = multdiv_sel ? multdiv_imd_val_d[1] : {2'b0, alu_imd_val_d[1]};
  assign imd_val_we_o   = multdiv_sel ? multdiv_imd_val_we : alu_imd_val_we;

  assign alu_imd_val_q = '{imd_val_q_i[0][31:0], imd_val_q_i[1][31:0]};

  assign result_ex_o  = multdiv_sel ? multdiv_result : alu_result;

  // branch handling
  assign branch_decision_o  = alu_cmp_result;


  //  initial begin
  //   $display("sample ", instr_rdata_ex_i);
  // end

  // Internal state variables (feedback mechanism)
    // logic [1:0] btb_data_wdata_state;
    // logic btb_data_write_state;

    // Default BTB address
    // assign btb_data_addr_o = instr_rdata_ex_i;
    feistel_encrypt  #(
    // .N_ROUNDS(4)
  ) feistel_encrypt_index (
    .plaintext(instr_rdata_ex_i),
    .round_keys(16'b1011110100111010),
    .ciphertext(btb_data_addr_o)
   );

    // Feedback logic for BTB data write enable
 assign btb_data_write_o = (!rst_ni) ? 1'b0 : 
                          (alu_instr_first_cycle_i) ? 1'b1 : 
                          1'b0;

    // Feedback logic for BTB data write value
assign btb_data_wdata_o = (!rst_ni) ? 2'b00 :
                          (alu_instr_first_cycle_i && branch_decision_o) ? (
                              (btb_data_rdata_i == 2'b00) ? 2'b01 :
                              (btb_data_rdata_i == 2'b01) ? 2'b10 :
                              (btb_data_rdata_i == 2'b10) ? 2'b11 :
                              2'b11 // Saturate at strongly taken
                          ) :
                          (alu_instr_first_cycle_i && !branch_decision_o) ? (
                              (btb_data_rdata_i == 2'b00) ? 2'b00 :
                              (btb_data_rdata_i == 2'b01) ? 2'b00 :
                              (btb_data_rdata_i == 2'b10) ? 2'b01 :
                              (btb_data_rdata_i == 2'b11) ? 2'b10 :
                              2'b00 // Saturate at strongly not taken
                          ) : 
                          btb_data_rdata_i; // Default to current data if no condition matches


  
  // /// BTB update
  //  // Add BTB update logic after branch decision
  // always_ff @(posedge clk_i or negedge rst_ni) begin
  //   if (!rst_ni) begin
  //     btb_data_write_o <= 1'b0;
  //     btb_data_wdata_o <= 2'b00;
  //   end else begin
  //     btb_data_write_o <= 1'b0;
      
  //     if (alu_instr_first_cycle_i && branch_decision_o) begin
  //       btb_data_write_o <= 1'b1;
  //       // Update counter based on actual outcome
  //       case (btb_data_rdata_i)
  //         2'b00: btb_data_wdata_o <= 2'b01; // Increment if taken
  //         2'b01: btb_data_wdata_o <= 2'b10;
  //         2'b10: btb_data_wdata_o <= 2'b11;
  //         2'b11: btb_data_wdata_o <= 2'b11; // Saturate at strongly taken
  //       endcase
  //     end else if (alu_instr_first_cycle_i && !branch_decision_o) begin
  //       btb_data_write_o <= 1'b1;
  //       // Decrement counter if not taken
  //       case (btb_data_rdata_i)
  //         2'b00: btb_data_wdata_o <= 2'b00; // Saturate at strongly not taken
  //         2'b01: btb_data_wdata_o <= 2'b00;
  //         2'b10: btb_data_wdata_o <= 2'b01;
  //         2'b11: btb_data_wdata_o <= 2'b10;
  //       endcase
  //     end
  //   end
  // end

  // // Use branch PC for BTB update
  // assign btb_data_addr_o = instr_rdata_ex_i;


  // /// BTB update





  if (BranchTargetALU) begin : g_branch_target_alu
    logic [32:0] bt_alu_result;
    // logic [31:0] bt_alu_result_enc;
    logic        unused_bt_carry;

    assign bt_alu_result   = bt_a_operand_i + bt_b_operand_i;
    
    

    assign unused_bt_carry = bt_alu_result[32];
    
    // wire is_jal = (instr_rdata_ex_i == 7'b1101111);  // Opcode for JAL
    // assign bt_alu_result_enc = (is_jal) ? (bt_alu_result[31:0] ^ 32'h82068860) : bt_alu_result[31:0];
    // assign bt_alu_result_enc = bt_alu_result[31:0] ^ 32'h82068860;

    // assign branch_target_o = bt_alu_result_enc;
    assign branch_target_o = bt_alu_result[31:0];

  end else begin : g_no_branch_target_alu
    // Unused bt_operand signals cause lint errors, this avoids them
    logic [31:0] unused_bt_a_operand, unused_bt_b_operand;

    assign unused_bt_a_operand = bt_a_operand_i;
    assign unused_bt_b_operand = bt_b_operand_i;

    assign branch_target_o = alu_adder_result_ex_o;
  end

  /////////
  // ALU //
  /////////

  // Your existing local signal declarations ...
  // logic [31:0] modified_alu_operand_a;

  // Opcode and JALR detection
  // wire [6:0] opcode = instr_rdata_ex_i[6:0];
  wire is_jalr = (instr_rdata_ex_i[6:0] == 7'b1100111);  // Opcode for JALR
  
  // wire is_jal = 1'b1;  // Opcode for JAL
  

  // Apply XOR operation if the instruction is JALR
  // (alu_operand_a_i ^ 32'h52068860)
  // assign modified_alu_operand_a =  (is_jalr) ? (alu_operand_a_i ^ 32'h52068860) : alu_operand_a_i;
  assign alu_result =  (is_jalr) ? (alu_result_raw ^ 32'h52068860) : alu_result_raw;
  assign alu_adder_result_ex_o =  (is_jalr) ? (alu_adder_result_ex_o_raw ^ 32'h52068860) : alu_adder_result_ex_o_raw;
  
  // $display("%b", modified_alu_operand_a);
  // $monitor(,$time,"a=%h",modified_alu_operand_a);

  ibex_alu #(
    .RV32B(RV32B)
  ) alu_i (
    .operator_i         (alu_operator_i),
    .operand_a_i        (alu_operand_a_i), //potential modified operand
    .operand_b_i        (alu_operand_b_i),
    .instr_first_cycle_i(alu_instr_first_cycle_i),
    .imd_val_q_i        (alu_imd_val_q),
    .imd_val_we_o       (alu_imd_val_we),
    .imd_val_d_o        (alu_imd_val_d),
    .multdiv_operand_a_i(multdiv_alu_operand_a),
    .multdiv_operand_b_i(multdiv_alu_operand_b),
    .multdiv_sel_i      (multdiv_sel),
    // .adder_result_o     (alu_adder_result_ex_o),
    .adder_result_o           (alu_adder_result_ex_o_raw),
    
    .adder_result_ext_o (alu_adder_result_ext),
    
    // .result_o           (alu_result), 
    .result_o           (alu_result_raw), 

    .comparison_result_o(alu_cmp_result),
    .is_equal_result_o  (alu_is_equal_result)
  );

  ////////////////
  // Multiplier //
  ////////////////

  if (RV32M == RV32MSlow) begin : gen_multdiv_slow
    ibex_multdiv_slow multdiv_i (
      .clk_i             (clk_i),
      .rst_ni            (rst_ni),
      .mult_en_i         (mult_en_i),
      .div_en_i          (div_en_i),
      .mult_sel_i        (mult_sel_i),
      .div_sel_i         (div_sel_i),
      .operator_i        (multdiv_operator_i),
      .signed_mode_i     (multdiv_signed_mode_i),
      .op_a_i            (multdiv_operand_a_i),
      .op_b_i            (multdiv_operand_b_i),
      .alu_adder_ext_i   (alu_adder_result_ext),
      .alu_adder_i       (alu_adder_result_ex_o),
      .equal_to_zero_i   (alu_is_equal_result),
      .data_ind_timing_i (data_ind_timing_i),
      .valid_o           (multdiv_valid),
      .alu_operand_a_o   (multdiv_alu_operand_a),
      .alu_operand_b_o   (multdiv_alu_operand_b),
      .imd_val_q_i       (imd_val_q_i),
      .imd_val_d_o       (multdiv_imd_val_d),
      .imd_val_we_o      (multdiv_imd_val_we),
      .multdiv_ready_id_i(multdiv_ready_id_i),
      .multdiv_result_o  (multdiv_result)
    );
  end else if (RV32M == RV32MFast || RV32M == RV32MSingleCycle) begin : gen_multdiv_fast
    ibex_multdiv_fast #(
      .RV32M(RV32M)
    ) multdiv_i (
      .clk_i             (clk_i),
      .rst_ni            (rst_ni),
      .mult_en_i         (mult_en_i),
      .div_en_i          (div_en_i),
      .mult_sel_i        (mult_sel_i),
      .div_sel_i         (div_sel_i),
      .operator_i        (multdiv_operator_i),
      .signed_mode_i     (multdiv_signed_mode_i),
      .op_a_i            (multdiv_operand_a_i),
      .op_b_i            (multdiv_operand_b_i),
      .alu_operand_a_o   (multdiv_alu_operand_a),
      .alu_operand_b_o   (multdiv_alu_operand_b),
      .alu_adder_ext_i   (alu_adder_result_ext),
      .alu_adder_i       (alu_adder_result_ex_o),
      .equal_to_zero_i   (alu_is_equal_result),
      .data_ind_timing_i (data_ind_timing_i),
      .imd_val_q_i       (imd_val_q_i),
      .imd_val_d_o       (multdiv_imd_val_d),
      .imd_val_we_o      (multdiv_imd_val_we),
      .multdiv_ready_id_i(multdiv_ready_id_i),
      .valid_o           (multdiv_valid),
      .multdiv_result_o  (multdiv_result)
    );
  end

  // Multiplier/divider may require multiple cycles. The ALU output is valid in the same cycle
  // unless the intermediate result register is being written (which indicates this isn't the
  // final cycle of ALU operation).
  assign ex_valid_o = multdiv_sel ? multdiv_valid : ~(|alu_imd_val_we);

`ifdef INC_ASSERT
  // This is intended to be accessed via hierarchal references so isn't output from this module nor
  // used in any logic in this module
  logic sva_multdiv_fsm_idle;

  if (RV32M == RV32MSlow) begin : gen_multdiv_sva_idle_slow
    assign sva_multdiv_fsm_idle = gen_multdiv_slow.multdiv_i.sva_fsm_idle;
  end else if (RV32M == RV32MFast || RV32M == RV32MSingleCycle) begin : gen_multdiv_sva_idle_fast
    assign sva_multdiv_fsm_idle = gen_multdiv_fast.multdiv_i.sva_fsm_idle;
  end else begin : gen_multdiv_sva_idle_none
    assign sva_multdiv_fsm_idle = 1'b1;
  end

  // Mark the sva_multdiv_fsm_idle as unused to avoid lint issues
  logic unused_sva_multdiv_fsm_idle;
  assign unused_sva_multdiv_fsm_idle = sva_multdiv_fsm_idle;
`endif

endmodule
