
module feistel_decrypt #(
    parameter int N_ROUNDS = 4 // Number of rounds from configuration file
)(
    // input logic clk, 
    input logic [7:0] ciphertext,   // 8-bit input data for decryption
    input logic [N_ROUNDS*4-1:0] round_keys, // Concatenated round keys (same as encryption)
    output logic [7:0] plaintext   // 8-bit decrypted output
);
    logic [3:0] left, right;       // Left and right halves of the data
    logic [3:0] next_left, next_right;
    
    initial begin
        left = ciphertext[7:4];     // Upper 4 bits as left half
        right = ciphertext[3:0];    // Lower 4 bits as right half
    end

    genvar i;
    generate 
        for (i = N_ROUNDS-1; i >= 0; i--) begin : feistel_rounds_reverse
            feistel_round fr (
                // .clk(clk),
                .left_in(left),
                .right_in(right),
                .round_key(round_keys[i*4 +: 4]), // Extracting each 4-bit round key in reverse order
                .left_out(next_left),
                .right_out(next_right)
            );
            always_comb begin
                left = next_left;
                right = next_right;
                if (left > 10 ) begin
                    $display("left: %d ", left);
                end
            end
        end
    endgenerate
    
    assign plaintext = {left, right}; // Combine final halves into plaintext
endmodule
