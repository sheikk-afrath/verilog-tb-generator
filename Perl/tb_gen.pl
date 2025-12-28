# Make sure the user provided a filename on the command line, or stop the script.
@ARGV || die "Enter design file name";

# Get the first command-line argument (e.g., "design.v") and store it.
$des_f = "$ARGV[0]";            # design filename

# Copy the design name to use as a base for the testbench filename.
$tb_f = $des_f;                 # testbench filename

# Insert "_tb" into the testbench filename, right before the last two characters.
# This turns "design.v" into "design_tb.v".
substr($tb_f,-2,0,"_tb");        

# This is a flag. We'll assume the design is combinational (1 = true) by default.
$combo = 1;

# Flag to track if we found a reset port
$rst_found = 0;

# Declare an empty array to store the names of all input ports (e.g., "data", "clk").
@in;
# Declare an empty array to store the *widths* of those input ports (e.g., "7", "1").
@in_w;
# Declare an empty array to store the names of all output ports (e.g., "result").
@out;
# Declare an empty array to store the *widths* of those output ports.
@out_w;

# Open the Verilog design file for reading. If it fails, stop with an error.
open FH1, "<$des_f" or die "error opening file: $!";
# Create and open the new testbench file (e.g., "design_tb.v") for writing.
open FH2, ">$tb_f" or die "error opening file: $!";

# Read the design file one line at a time. Each line is stored in $_.
while(<FH1>) {
    
    # Check if the line starts with "module" followed by a name and an opening parenthesis.
    if($_ =~ /^module\s+(\w+)\s*\(/) {
        # The \( is a "literal parenthesis", needed so regex doesn't think it's a special character.
        
        # Save the captured module name (the part in (\w+)) into our $module variable.
        $module = $1;
    }
    # Else, check if the line is an input port declaration.
    # This regex is smart: it optionally matches a vector width [XX:0].
    elsif($_ =~ /\s*input\s+\w*\s*(?:\[\s*(\d+):\d+\s*\])?\s*(\w+).+/) {		
        # The (.+) at the end matches the rest of the line (like a comma or semicolon).
        
        # This is a ternary operator. 
        # If we captured a width ($1 is defined), use it. 
        # Otherwise (it's a single bit), use '1' as a special flag.
        $data_width_i = defined($1) ? $1 : 1;
        
        # Add the captured port name (e.g., "data") to our @in array.
        push(@in,$2);
        # Add the corresponding width (e.g., "7" or "1") to our @in_w array.
        push(@in_w,$data_width_i);
    }
    # Else, check if the line is an output port declaration.
    # This also handles "output reg [...]".
    elsif($_ =~ /\s*output\s+\w*\s*(?:\[\s*(\d+):\d+\s*\])?\s*(\w+).+/) {
        # Again, (.+) matches the rest of the line.
        
        # Get the output width, defaulting to '1' if it's not a vector.
        $data_width_o = defined($1) ? $1 : 1;
        
        # Add the captured port name to our @out array.
        push(@out,$2);
        # Add the corresponding width to our @out_w array.
        push(@out_w,$data_width_o);
    }
} # We're done reading the input file, so the while-loop ends.

# --- Parsing is done. Now, figure out what we found. ---

# Check if a clock signal exists.
for ($i = $#in; $i >= 0; $i--) {
    # Loop through all the input names we found.
    if ($in[$i] eq "clk" or $in[$i] eq "clock") {
        # If we find "clk" or "clock"...
        
        # ...it's a sequential circuit! Set the 'combo' flag to 0 (false).
        $combo = 0;
        
        # Store the exact name of the clock (e.g., "clk").
        $clk = $in[$i]; 
        
        # Copy the full input list (with the clock) into @inm for module instantiation.
        @inm = @in;
		# Copy it's corresponding widths
		@inm_w = @in_w;
        
        # Remove the clock from the main @in list, so we don't try to assign it random values later.
        splice(@in,$i,1);
        # Splice the width array to keep them in sync
        splice(@in_w,$i,1); 
    }
}

# Check for a reset signal (looping through the *remaining* inputs).
for ($i = $#in; $i >= 0; $i--) {
    
    # Check for an active-high reset.
    if ($in[$i] eq "rst" or $in[$i] eq "reset") {
		$rst_found = 1;
        # Set the active value to 1.
        $rst_active = 1;
        # Set the inactive value to 0.
        $n_rst_active = 0;
        # Store the reset's name.
        $rst = $in[$i];
        # Remove the reset from the @in list (so we don't randomize it).
        splice(@in,$i,1);
        # Remove the reset's width from the @in_w list to keep them in sync.
        splice(@in_w,$i,1);
    }
    # Check for an active-low reset (Note: rst_n should be in quotes).
    elsif ($in[$i] eq "rst_n" or $in[$i] eq "reset_n") {
		$rst_found = 1;
        # Set the active value to 0.
        $rst_active = 0;
        # Set the inactive value to 1.
        $n_rst_active = 1;
        # Store the reset's name.
        $rst = $in[$i];
        # Remove the reset from the @in list.
        splice(@in,$i,1);
        # Remove its width from the @in_w list.
        splice(@in_w,$i,1);
    }
}

# --- Logic is done. Now, write the testbench file. ---

# Write the timescale directive at the top of the file.
print FH2 "\`timescale 1ns/1ps\n\n";

# Write the module declaration (e.g., "module design_tb();").
print FH2 "module $module\_tb()\;\n";

# Add a blank line for readability.
print FH2 "\n";

# --- Declare registers for inputs ---

# If the circuit was purely combinational...
if ($combo == 1) {
    # ...then the module input list is just the @in list (no clock was removed).
    @inm = @in;
	@inm_w = @in_w;
}
# Loop through the module's input list (this one *includes* clock and reset).
for ($i=0; $i<@inm; $i++) {
    # Check if the width is our special '1' (meaning 1-bit).
    if ($inm_w[$i] == 1) {
        # Print a simple 'reg' declaration (e.g., "reg clk;").
        print FH2 "reg $inm[$i]\;\n"
    }
    # Otherwise, it's a vector.
    else {
        # Print a vector 'reg' declaration (e.g., "reg [7:0]data;").
        print FH2 "reg [$inm_w[$i]:0]$inm[$i]\;\n"
    }
}

# Add a blank line for readability.
print FH2 "\n";

# --- Declare wires for outputs ---

# Loop through all the output ports we found.
for ($i=0; $i<@out; $i++) {
    # Check if it's a 1-bit signal.
    if ($out_w[$i] == 1) {
        # Print a simple 'wire' declaration (e.g., "wire q;").
        print FH2 "wire $out[$i]\;\n"
    }
    # Otherwise, it's a vector.
    else {
        # Print a vector 'wire' declaration (e.g., "wire [3:0]result;").
        print FH2 "wire [$out_w[$i]:0]$out[$i]\;\n"
    }
}

# Add a blank line for readability.
print FH2 "\n";

# --- Instantiate the Module (Device Under Test) ---

# Create one big array of all ports (inputs first, then outputs).
@inout = (@inm,@out);

# Print the start of the instantiation (e.g., "design dut (").
print FH2 "$module dut \(";

# Loop through the combined list of all ports.
for($i=0; $i<@inout; $i++) {
    # Print the named port connection (e.g., ".data(data)").
    print FH2 ".$inout[$i]\($inout[$i]\)";
    
    # Check if this is the very last port in the list.
    if ($i==@inout-1){
        # If it is, close the parenthesis and end the line.
        print FH2 "\);\n";
    }
    # Otherwise...
    else {
        # ...print a comma to separate it from the next port.
        print FH2 ",";
    }
}
# Add a blank line for readability.
print FH2 "\n";

# --- Create Testbench Logic ---

# Generate the clock, but only if it's a sequential circuit.
print FH2 "always #5 $clk = \~$clk\;\n\n" if ($combo == 0);

# Start the 'initial' block where all the stimulus happens.
print FH2 "initial begin\n";

# Add a blank line for readability.
print FH2 "\n";

# If it's a sequential circuit, add the clock and reset initialization.
if ($combo == 0) {
    # Start the clock at 0.
    print FH2 "$clk = 1\'b0\;\n";
	
	# Only print reset logic if a reset was found
    if ($rst_found) {
        # Start the reset in its inactive state. (Added \t)
        print FH2 "$rst = 1\'b$n_rst_active\;\n";
        # Wait 10 time units, then assert the reset (active state). (Added \t)
        print FH2 "#10 $rst = 1\'b$rst_active\;\n";
        # Wait 10 more time units, then de-assert the reset (back to inactive). (Added \t)
        print FH2 "#10 $rst = 1\'b$n_rst_active\;\n\n";
    }
}

# Start an outer loop that will run 10 times, creating 10 test vectors.
for($i=0; $i<10; $i++) {
    
    # Print a 10-time-unit delay into the testbench file.
    # This separates each new set of random inputs.
	print FH2 "#10;\n";

    # Start an inner loop to iterate through each randomizable input
    # (this @in array excludes 'clk' and 'rst').
	for ($j=0; $j<@in; $j++) {
        
        # Calculate the total bit width for the Verilog assignment.
        # If $in_w[$j] is 1 (our flag for a 1-bit signal), $width_for_rand becomes 1.
        # If $in_w[$j] is 7 (for a [7:0] vector), $width_for_rand becomes 7 + 1 = 8.
		$width_for_rand = ($in_w[$j] == 1) ? 1 : ($in_w[$j] + 1);
		
        # Generate a random integer within the correct range.
        # 2**$width_for_rand is the "power of" operator (e.g., 2**8 = 256).
        # rand(256) gives a value from 0 to 255.999...
        # int() converts it to an integer (e.g., 0 to 255).
		$random = int(rand(2**$width_for_rand));
		
        # Print the final Verilog line to the testbench file.
        # This will look like: "data_in = 8'd123;" or "enable = 1'd1;".
		print FH2 "\t$in[$j] = $width_for_rand\'d$random\;\n";
	}
    
    # After all inputs are assigned for this time step, print a blank line
    # in the .v file to make the testbench easier to read.
	print FH2 "\n";
	
}
# After the loop finishes, wait 50 more time units.
print FH2 "#50 \$stop\;\n\n";

# Close the 'initial' block.
print FH2 "end\n";
# Close the testbench module.
print FH2 "endmodule\n";
