
module feistel_round(
    // input logic clk, 
    input logic [3:0] left_in,   // Left half of the data
    input logic [3:0] right_in,  // Right half of the data
    input logic [3:0] round_key, // Round key (can be generated or fixed)
    output logic [3:0] left_out, // New left half after round
    output logic [3:0] right_out // New right half after round
);
    // Simple XOR-based round function
     logic [3:0] f_output;
    always_comb begin
        
        assign f_output = right_in ^ round_key;
        assign right_out = left_in ^ f_output; // Example round function
        
        assign left_out = right_in;

    end
   
  
endmodule


//   always @(posedge clk) begin
//         if(left_in == 4  ) begin
//             $display("left: %d ", left_in);
//         end
//     end


// module feistel_round (
//     input  logic        clk,
//     input  logic        rst,
//     input  logic [3:0]  left_in,
//     input  logic [3:0]  right_in,
//     input  logic [3:0]  round_key,
//     output logic [3:0]  left_out,
//     output logic [3:0]  right_out
// );

//     logic [3:0] f_output;

//     // Round function F
//     always_comb begin
//         f_output = right_in ^ round_key;
//     end

//     // Round computation
//     always_ff @(posedge clk) begin
//         if (rst) begin
//             left_out  <= '0;
//             right_out <= '0;
//         end else begin
//             left_out  <= right_in;
//             right_out <= left_in ^ f_output;
//         end
//     end

// endmodule