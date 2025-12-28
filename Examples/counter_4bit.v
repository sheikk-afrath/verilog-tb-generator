module counter_4bit (
    input clk,
    input rst_n,
    input enable,
    output reg [3:0] count_out
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            count_out <= 4'b0000;
        else if (enable)
            count_out <= count_out + 1;
    end

endmodule