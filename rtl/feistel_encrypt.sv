

// // ***** this works fine but it is sequential circuit and takes 4 cycles *****


// module feistel_encrypt #(
//     parameter int N_ROUNDS = 4 // Number of rounds from configuration file
// )(
//     input logic clk,              // Add clock signal for sequential updates
//     input logic [7:0] plaintext,  // 8-bit input data for encryption
//     input logic [N_ROUNDS*4-1:0] round_keys, // Concatenated round keys (4 bits per round)
//     output logic [7:0] ciphertext  // 8-bit encrypted output
// );

//     logic [3:0] left, right;       // Left and right halves of the data
//     logic [3:0] next_left, next_right;

//     // Initialize left and right halves from plaintext
//     // always_ff @(posedge clk) begin
//     //     left <= plaintext[7:4];     // Upper 4 bits as left half
//     //     right <= plaintext[3:0];    // Lower 4 bits as right half
//     // end
//     initial begin
//         left = plaintext[7:4];     // Upper 4 bits as left half
//         right = plaintext[3:0];    // Lower 4 bits as right half
//     end

//     genvar i;
//     generate 
//         for (i = 0; i < N_ROUNDS; i++) begin : feistel_rounds
//             feistel_round fr (
//                 // .clk(clk),
//                 .left_in(left),
//                 .right_in(right),
//                 .round_key(round_keys[i*4 +: 4]), // Extracting each 4-bit round key
//                 .left_out(next_left),
//                 .right_out(next_right)
//             );

//             // Sequentially update left and right on each clock cycle
//             always_ff @(posedge clk) begin
//                 left <= next_left;
//                 right <= next_right;
//                 // if (left > 10 ) begin
                
//                 // end
//             end
//         end
//     endgenerate

//     // Combine final halves into ciphertext after all rounds are done
    
//     assign ciphertext = {left, right};

//     // always @(posedge clk) begin
//     //     $display("left: %d ", plaintext, " right: %d ", ciphertext);
//     // end

// endmodule
// // ***** this works fine *****



module feistel_encrypt #(
    // parameter int N_ROUNDS = 4
) (
    input  logic [7:0]  plaintext,
    input  logic [15:0] round_keys,
    output logic [7:0]  ciphertext
);

    // logic [3:0] round_left  [N_ROUNDS+1];
    // logic [3:0] round_right [N_ROUNDS+1];

    logic [3:0] round_left  ;
    logic [3:0] round_right ;

    logic [3:0] round_left_2  ;
    logic [3:0] round_right_2 ;

     logic [3:0] round_left_3  ;
    logic [3:0] round_right_3 ;

     logic [3:0] round_left_4  ;
    logic [3:0] round_right_4 ;

    logic [3:0] next_left_out;
     logic [3:0] next_right_out;

    // Input assignment
    assign round_left  = plaintext[7:4];
    assign round_right = plaintext[3:0];


  
    

    // Generate N_ROUNDS of Feistel rounds
    // genvar i;
    generate
    // awalys
        // for (i = 0; i < N_ROUNDS; i++) begin : feistel_rounds
            
        //     feistel_round round_inst (
        //         .left_in  (round_left[i]),
        //         .right_in (round_right[i]),
        //         .round_key(round_keys[i*4 +: 4]),
        //         .left_out (round_left[i+1]),
        //         .right_out(round_right[i+1])
        //     );

             feistel_round round_inst (
                .left_in  (round_left),
                .right_in (round_right),
                .round_key(round_keys[0*4 +: 4]),
                .left_out (round_left_2),
                .right_out(round_right_2)
            );

              feistel_round round_inst_2 (
                .left_in  (round_left_2),
                .right_in (round_right_2),
                .round_key(round_keys[1*4 +: 4]),
                .left_out (round_left_3),
                .right_out(round_right_3)
            );


            feistel_round round_inst_3 (
                .left_in  (round_left_3),
                .right_in (round_right_3),
                .round_key(round_keys[2*4 +: 4]),
                .left_out (round_left_4),
                .right_out(round_right_4)
            );

            feistel_round round_inst_4 (
                .left_in  (round_left_4),
                .right_in (round_right_4),
                .round_key(round_keys[3*4 +: 4]),
                .left_out (next_left_out),
                .right_out(next_right_out)
            );
        // end
    endgenerate

    // assign ciphertext = {round_right[N_ROUNDS + 1], round_left[N_ROUNDS + 1]};
   
    // assign round_left[0]  = plaintext[7:4];
    // assign round_right[0] = plaintext[3:0];
    assign ciphertext = {next_right_out, next_left_out};

endmodule

