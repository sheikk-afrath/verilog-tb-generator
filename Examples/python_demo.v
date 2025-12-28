module python_demo (
    input clk,
    input [0:7] ascending_data,
    input [31:16] upper_bus,
    output reg [63:32] result_bus
);

    always @(posedge clk) begin
        result_bus <= {upper_bus, upper_bus} + ascending_data;
    end

endmodule