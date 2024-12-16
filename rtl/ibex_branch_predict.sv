
// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

/**
 * Branch Predictor
 *
 * This implements static branch prediction. It takes an instruction and its PC and determines if
 * it's a branch or a jump and calculates its target. For jumps it will always predict taken. For
 * branches it will predict taken if the PC offset is negative.
 *
 * This handles both compressed and uncompressed instructions. Compressed instructions must be in
 * the lower 16-bits of instr.
 *
 * The predictor is entirely combinational but takes clk/rst_n signals for use by assertions.
 */

`include "prim_assert.sv"

module ibex_branch_predict (
 

  // Instruction from fetch stage
  input  logic [31:0] fetch_rdata_i,
  input  logic [31:0] fetch_pc_i,
  input  logic        fetch_valid_i,

  // Prediction for supplied instruction
  output logic        predict_branch_taken_o,
  output logic [31:0] predict_branch_pc_o,


  input  logic clk_i,
  input  logic rst_ni,

  output logic                        btb_data_write_o, 
  output logic [7:0]                  btb_data_addr_o,
  // output logic [1:0]                  btb_data_wdata_o,
  input  logic                        btb_data_rdata_i
//   output logic                        ready

  // BTB handshaking
  // output logic                        btb_req_o,
  // input  logic                        btb_ready_i,
  // output logic                        ready

);
  import ibex_pkg::*;

  logic [31:0] imm_j_type;
  logic [31:0] imm_b_type;
  logic [31:0] imm_cj_type;
  logic [31:0] imm_cb_type;

  logic [31:0] branch_imm;

  // logic [31:0] instr;

  logic instr_j;
  logic instr_b;
  logic instr_cj;
  logic instr_cb;

  logic [15:0] temp_16b_instr;// kalab
  logic [31:0] temp_32b_instr;// kalab
  
  assign temp_16b_instr = ( {2'b00, (fetch_rdata_i[15:2] ^ 14'h2844 ^ fetch_pc_i[13:0]) }  << 2) |  {14'h00000, fetch_rdata_i[1:0] }; // kalab
  assign temp_32b_instr = ( {2'b00, (fetch_rdata_i[31:2] ^ 30'h34640911 ^ fetch_pc_i[29:0]) } << 2) | {30'h0000, fetch_rdata_i[1:0] };// kalab
  


  // logic instr_b_taken;

  // logic [1:0]  btb_data;  // Register to sample BTB data

    // BTB lookup state
    // enum logic [1:0] {
    //   IDLE,
    //   LOOKUP,
    //   PREDICT
    // } state_q, state_d;

    // Branch address for BTB

    logic [7:0] btb_data_addr_o_temp;

  // assign btb_data_addr_o = fetch_pc_i[7:0];  // Use 7 bits of PC for BTB indexing
  assign btb_data_addr_o_temp = fetch_pc_i[7:0];  // Use 7 bits of PC for BTB indexing
  
   
  feistel_encrypt  #(
    // .N_ROUNDS(4)
  ) feistel_encrypt_index (
    .plaintext(btb_data_addr_o_temp),
    .round_keys(16'b1011110100111010),
    .ciphertext(btb_data_addr_o)
   );
  

  // Provide short internal name for fetch_rdata_i due to reduce line wrapping
  // assign instr = fetch_rdata_i;

  // Extract and sign-extend to 32-bit the various immediates that may be used to calculate the
  // target

  // Uncompressed immediates
  assign imm_j_type = { {12{temp_32b_instr[31]}}, temp_32b_instr[19:12], temp_32b_instr[20], temp_32b_instr[30:21], 1'b0 };
  assign imm_b_type = { {19{temp_32b_instr[31]}}, temp_32b_instr[31], temp_32b_instr[7], temp_32b_instr[30:25], temp_32b_instr[11:8], 1'b0 };

  // Compressed immediates
  assign imm_cj_type = { {20{temp_16b_instr[12]}}, temp_16b_instr[12], temp_16b_instr[8], temp_16b_instr[10:9], temp_16b_instr[6], temp_16b_instr[7],
    temp_16b_instr[2], temp_16b_instr[11], temp_16b_instr[5:3], 1'b0 };

  assign imm_cb_type = { {23{temp_16b_instr[12]}}, temp_16b_instr[12], temp_16b_instr[6:5], temp_16b_instr[2], temp_16b_instr[11:10],
    temp_16b_instr[4:3], 1'b0};

  // Determine if the instruction is a branch or a jump

  // Uncompressed branch/jump
  assign instr_b = opcode_e'(temp_32b_instr[6:0]) == OPCODE_BRANCH;
  assign instr_j = opcode_e'(temp_32b_instr[6:0]) == OPCODE_JAL;

  // Compressed branch/jump
  assign instr_cb = (temp_16b_instr[1:0] == 2'b01) & ((temp_16b_instr[15:13] == 3'b110) | (temp_16b_instr[15:13] == 3'b111));
  assign instr_cj = (temp_16b_instr[1:0] == 2'b01) & ((temp_16b_instr[15:13] == 3'b101) | (temp_16b_instr[15:13] == 3'b001));

  // Select out the branch offset for target calculation based upon the instruction type
  always_comb begin
    branch_imm = imm_b_type;

    unique case (1'b1)
      instr_j  : branch_imm = imm_j_type;
      instr_b  : branch_imm = imm_b_type;
      instr_cj : branch_imm = imm_cj_type;
      instr_cb : branch_imm = imm_cb_type;
      default : ;
    endcase
  end

  // Sample BTB data when ready
  // always_ff @(posedge clk_i or negedge rst_ni) begin
  //   if (!rst_ni) begin
  //     btb_data <= 2'b00;
  //   end else if (state_q == LOOKUP && btb_ready_i) begin
  //     btb_data <= btb_data_rdata_i;
  //   end
  // end

//   // temp
//     always_comb begin
//     // Default outputs
//     btb_data_write_o = 1'b0;
//     predict_branch_taken_o = 1'b0;

//     // Combinational logic based on inputs
//     if (fetch_valid_i) begin
//         if (instr_b || instr_cb) begin
//             // Predict branch taken based on BTB data
//             predict_branch_taken_o = btb_data_rdata_i;
//         end else if (instr_j || instr_cj) begin
//             // Direct jump prediction
//             predict_branch_taken_o = 1'b1;
//         end
//     end
// end

 // Default assignments
    assign btb_data_write_o = 1'b0; // branch predictor does not write to BTB

    // Combinational logic for predict_branch_taken_o
    assign predict_branch_taken_o = (fetch_valid_i && (instr_j || instr_cj)) ? 
                                    1'b1 : 
                                    ((fetch_valid_i && (instr_b || instr_cb)) ? btb_data_rdata_i : 1'b0);



  ///


//    // State machine for BTB lookup
//   always_ff @(posedge clk_i or negedge rst_ni) begin
//     if (!rst_ni) begin
//       state_q <= IDLE;
//     end else begin
//       state_q <= state_d;
//     end
//   end

//   // BTB lookup and prediction logic
//   always_comb begin
//     state_d = state_q;
//     ready = 1'b0;
//     btb_data_write_o = 1'b0; // branch predictor does not write to BTB
//     predict_branch_taken_o = 1'b0;
//     // btb_req_o = 1'b0;

//     case (state_q)
//       IDLE: begin
//         if (fetch_valid_i && (instr_b || instr_cb)) begin
//           $display("stuck in idle: %0d", instr);
//           // state_d = LOOKUP;
//           state_d = PREDICT;
//           // btb_req_o = 1'b1;
//         end else if (fetch_valid_i && (instr_j || instr_cj)) begin
//           // Direct jump, no need to check BTB because it this two are for sure jumps
//           state_d = PREDICT;
//         end
//       end
      
//       LOOKUP: begin
//         $display("stuck in lookup: %0d", instr);
//         // btb_req_o = 1'b1;
//         // if (btb_ready_i) begin
//         //   state_d = PREDICT;
//         // end
//         state_d = PREDICT;
//       end
      
//       PREDICT: begin
//         $display("stuck in predict: %0d", instr);
//         ready = 1'b1;
//         if (instr_j || instr_cj) begin
//           predict_branch_taken_o = 1'b1;
//         end else if (instr_b || instr_cb) begin
//           // Take branch if counter is 2'b10 or 2'b11
//           // predict_branch_taken_o = btb_data[1];
//           predict_branch_taken_o = btb_data_rdata_i;
//         end
//         state_d = IDLE;
//       end
      
//       default: state_d = IDLE;
//     endcase
//   end




  `ASSERT_IF(BranchInsTypeOneHot, $onehot0({instr_j, instr_b, instr_cj, instr_cb}), fetch_valid_i)

  // Determine branch prediction, taken if offset is negative
  // assign instr_b_taken = (instr_b & imm_b_type[31]) | (instr_cb & imm_cb_type[31]);

  // Always predict jumps taken otherwise take prediction from `instr_b_taken`
  // assign predict_branch_taken_o = fetch_valid_i & (instr_j | instr_cj | instr_b_taken);
  // Calculate target
  assign predict_branch_pc_o    = fetch_pc_i + branch_imm;
endmodule
