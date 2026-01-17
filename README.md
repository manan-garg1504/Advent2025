# Advent of FPGA 2025 - Problem 11

This repo contains a solution to Jane Street's Advent of Code 2025, Problem 11 - but written in RTL. I chose this problem because it looks like a very standard problem to solve in software, and I wanted to see just how different implementing a graph on an FPGA would be.

## How to use
I used the iverilog simulator to compile and test the design. Simply go into the directory (`parta` or `partb`) and run `iverilog -g2005-sv  -o top_level -c file_list.txt` to compile and  `vvp top_level -fst` to run. The input has to be in `input.txt` within this directory.

## Solution overview

### Processing the input
To ensure that the input interface is constant across any problems I might solve, the testbench will read the input from a file and send it to the design, one character per clock cycle. The design has the ability to apply backpressure to the testbench.

For this problem, we first reduce the inputs to 15-bit node strings (5 bits for each alphabet), and a single bit representing a newline. This is buffered through a small FIFO and passed into a hash table, which assigns a 12-bit number to every node string. This is done to reduce the space taken up by the rest of the hardware, and allows for 4096 servers - more than enough for the current input size. (It takes 1 BRAM with the current design to support 4096, the hash table can be easily scaled for more inputs).

### Graph initialization
The output of the hash table goes into the nodesets, where we start doing a few things in parallel:
- Storing the list of downstream servers. This info is written into a 36x512 SDP BRAM, so consumes half a BRAM on the FPGA. The first 64 addresses in each nodeset store the number of downlinks and the pointer to the list within the BRAM. The rest is used dynamically based on how many links each server has.
- For each server, we want to know how many "parent" servers can ultimately receive data from the starting server ("you" in part 1). For this, as soon as we have written the list for the starter server, we start sending signals over a switch network (more below) which informs downstream nodes that they are connected to "you". This is a recursive process, a server will inform its children when it is marked and its list is recieved. Our switch network is not overwhelmed because we only ever send one request over it per actual link.

### Final calculation
After the file read is completed, we wait for the initialization to complete. This hardly takes any time, because the initialization was mostly happening in parallel.

Once done, we change a global signal to inform all sub-modules that we are in the calculation stage. This process is very similar to the initialization, and uses most of the same hardware. In each nodeset, there is a 64x64 memory to store the number of paths counted from "you" to that node. This will most likely be impplemented as a LUTRAM.

At the start of the calc stage, the num_paths for the starter node is set to 1, and its counter (for number of paths from starter node) is decremented from 1 to 0. This again begins a recursive process where the parent nodes send their num_paths to children nodes once they themselves have recieved all their parents' values. We again avoid congesting out switch network because we only send signals once per node.

There is a separate listener module connected to the output of the switch network, which is used to monitor the requests recieved for the output node. This module can thus sum up all the paths coming for the "out" node and give us our answer.

### Switch network
This is a mesh of small FIFOs (depth 4) designed exchange requests between these nodesets. There are 64 nodesets, and the switch network takes 2 stages of FIFOs from input to output. This is a very simple design, and we don't have fairness requirements either. 

### Partb
This time, we need to count paths that specifically pass through two given points. The approach I've thought of is to add two bits into the payload (along with the number of paths), each bit representing whether dac and fft have been counted in the current path or not. This gives a hierarchy to the numbers we have stored at a node, and we have to discard points counted up till now if we get an input path which has traversed over mode of the special nodes. The rest of the setup can remain exactly the same.

## Further ideas
- Scaling: As it stands, this solution is very fixed with its parameters: The only thing that can really be easily changed is the bit width for the result. The design itself can handle a large range of input, but has a limit. The simplest method to scale it would be to double the depth of the hash table and the same for the nodeset memory. Increasing the number of nodesets will cause issues with address widths and needing to change the switch network. This would be cumbersome in verilog, and is a good playground for trying out better languages.
- One method to further reduce latency would be to also store the reversed lists, and mark the downstream nodes of "out" as well. We could then ignore unmarked nodes during the calculation stage. I don't personally think this is a good idea because we'll be doubling memory usage for very little latency gain - most of the time currently goes in reading the file, and this will only accelerate the stage after.
- Making the switch network _less_ powerful: currently, the switch network can service at max 64 transactions a cycle. Given that our bottleneck is reading the input anyway, we can probably reduce hardware utilization and still get nearly the same performance - maybe even by reducing the number of nodesets.
- For partb, another approach would be to count the number of paths in each segment (There are three segments here) and then multiply the resulting three numbers. To do this, we would have to add three starting nodes (blocks to initiate counting, that is) and three listeners. We can look for paths from dac->fft during initialization to see which node comes first, so that we configure the starting and ending nodes correctly during counting.
