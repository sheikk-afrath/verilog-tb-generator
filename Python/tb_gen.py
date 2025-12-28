import re
import random
import sys

if len(sys.argv) < 2:
    print("Usage: python tb_gen.py <verilog_file.v>")
    sys.exit(1)

vfile = sys.argv[1]

# time period of clock
tclk = 10

# delay between each input vectors
delay = 13

# opening design file in read mode
ds = open(vfile)

# empty dictionary for inputs to store the input name it's corresponding bus width
in_dict = {}

# empty dict for reg declaration in tb for inputs
inreg_dict = {}

# empty dict for outputs
out_dict = {}

# assuming the design is combinational by defualt
combo = 1

# initializing reset string as empty
rst = ""

# iterating through each line in the design file
for line in ds:

    # saving module name
    if(x := re.search(r"\bmodule\s+(\w+)", line)):
        print(f"Module name is: {x.group(1)}")
        module = x.group(1)  # storing the module name string
    
    # saving inputs
    # regex to capture MSB (group 1), LSB (group 2), and Name (group 3)
    elif(x := re.search(r"^\s*input\s+(?:wire\s+)?(?:\[(\d+)\s*:\s*(\d+)\]\s*)?(\w+)", line)):
        #(?:...)?	Non-capturing Group:	Group logic together, but don't save the text.
        if(x.group(1) and x.group(2)):
            # storing list: [width, MSB, LSB]. Calculated using absolute difference + 1
            in_dict[x.group(3)] = [abs(int(x.group(1)) - int(x.group(2))) + 1, int(x.group(1)), int(x.group(2))]
        else:
            # storing list with single element for scalar inputs
            in_dict[x.group(3)] = [1]

    # saving outputs
    # regex to capture MSB (group 1), LSB (group 2), and Name (group 3)
    elif(x := re.search(r"^\s*output\s+(?:reg\s+)?(?:\[(\d+)\s*:\s*(\d+)\]\s*)?(\w+)", line)):
        if(x.group(1) and x.group(2)):
            # storing list: [width, MSB, LSB]. Calculated using absolute difference + 1
            out_dict[x.group(3)] =  [abs(int(x.group(1)) - int(x.group(2))) + 1, int(x.group(1)), int(x.group(2))]
        else:
            # storing list with single element for scalar inputs
            out_dict[x.group(3)] = [1]

# merging input and output dict for module instantiaion
inout_dict = in_dict | out_dict

# inputs for reg declaration
inreg_dict = in_dict.copy()

# checking for clock signal to make the combinational flag as zero
for i in in_dict:
    # checking if the input name matches common clock names
    if(i == "clk" or i == "clk_n" or i == "clock" or i == "clock_n"):
        combo = 0  # setting combinational flag to false (it is sequential)
        clk = i  # saving the clock variable name

    # checking if the input name matches common reset names
    elif(i == "rst" or i == "rst_n" or i == "reset" or i == "reset_n"):
        rst = i  # saving the reset variable name
        # checking if reset is active low (ends with _n)
        if(a := re.search(r"_n$", rst)):
            rst_h = 0
            rst_l = 1
        else: 
            rst_h = 1
            rst_l = 0




if(not combo):
    # removing clk and rst from the dict for initial block 
    del in_dict[clk]
    if(rst):
        del in_dict[rst]
    print(f"in_dict after removing clock and reset(if present): {in_dict}")


# -----------------writing the testbench-----------------------------

# file name for testbench
tbfile = vfile[:-2] + "_tb" + vfile[-2:]

# opening testbench file in write mode
tb = open(tbfile, "w")

# timescale
tb.write("`timescale 1ns/10ps\n\n")

# tb module declaration
tb.write("module " + module + "_tb;\n")

# reg(input) declaration
for (i,j) in inreg_dict.items():
    if(j[0]>1):
        # using stored MSB (j[1]) and LSB (j[2]) for correct vector declaration
        tb.write("reg [" + str(j[1]) + ":"+ str(j[2]) + "] " + str(i) + ";\n")
    else:
        tb.write("reg " + str(i) + ";\n")  # writing scalar register declaration

# wire(output) declaration
for (i,j) in out_dict.items():
    if(j[0]>1):
        # using stored MSB (j[1]) and LSB (j[2]) for correct vector declaration
        tb.write("wire [" + str(j[1]) + ":"+ str(j[2]) + "] " + str(i) + ";\n")
    else:
        tb.write("wire " + str(i) + ";\n")  # writing scalar wire declaration

# DUT Module instantiation
tb.write("\n//Module instantiation\n")
tb.write(module + " dut (\n")
for i in inout_dict:
    tb.write("\t." + str(i) + "(" + str(i) + ")")  # mapping ports by name
    if(i != list(inout_dict)[-1]):
    # Get the last key specifically
    # list(inout_dict) converts keys to a list, [-1] gets the last one
        tb.write(",\n")  # adding comma if it is not the last port
    else:
        tb.write("\n\t);\n")  # closing the instantiation parenthesis

# Clock generation (only for sequential)
tb.write("\n")
if (not combo):
    tb.write("always #"+ str(tclk/2) + " " + clk + " = ~" + clk + ";\n")

# Initial block
tb.write("\ninitial begin\n")
if (not combo):
    tb.write("\t" + clk + " = 1'b0;\n")  # initializing clock to 0
for (i,j) in in_dict.items():
    # initializing inputs to 0. Accessing j[0] for the width.
    tb.write("\t" + i + " = " + str(j[0]) + "\'d0" + ";\n")
if(rst):
    tb.write("\t" + rst + " = 1\'b" + str(rst_h) + ";\n")  # asserting reset
    tb.write("\n#" + str(delay) + "\t" + rst + " = 1\'b" + str(rst_l) + ";\n")

tb.write("\n")

for i in range(1,11):
    tb.write("#" + str(delay))  # adding delay before new vector
    for (j,k) in in_dict.items():
        # generating random value based on width (k[0])
        tb.write("\t" + j + " = "+ str(k[0]) +"\'d" + str(random.randint(0,(2**k[0]) - 1)) + ";\n")
    tb.write("\n")

tb.write("\n#50\t$stop;\n")  # stopping simulation after some time

tb.write("end\n\n")  # ending initial block
tb.write("endmodule\n")  # ending testbench module


ds.close()
tb.close()