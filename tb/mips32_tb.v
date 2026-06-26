`timescale 1ns/1ps

module mips32_tb;

    // Testbench signals
    reg clk1;
    reg clk2;

    // Instantiate the Device Under Test (DUT)
    mips32 dut (
        .clk1(clk1),
        .clk2(clk2)
    );

    //---------------------------------------------------------
    // Clock Generation (2-Phase Non-Overlapping)
    //---------------------------------------------------------
    initial begin
        clk1 = 0;
        clk2 = 0;
        
        // Ensure initial block in DUT has time to execute (PC=0, Reg=0)
        #1; 
        
        forever begin
            #5 clk1 = 1; #5 clk1 = 0;
            #5 clk2 = 1; #5 clk2 = 0;
        end
    end

    //---------------------------------------------------------
    // Stimulus & Memory Initialization
    //---------------------------------------------------------
    initial begin
        // Wait a moment for DUT's internal "initial" block to zero out arrays
        #2;

        // Load a small test program into the DUT's Instruction Memory
        // -----------------------------------------------------------
        
        // Instruction 1: ADDI R1, R0, 5  (Opcode: 10, rs: 0, rt: 1, imm: 5)
        // Binary: 001010_00000_00001_0000000000000101 -> Hex: 32'h2801_0005
        dut.Mem[0] = 32'h2801_0005;

        // Instruction 2: ADDI R2, R0, 10 (Opcode: 10, rs: 0, rt: 2, imm: 10)
        // Binary: 001010_00000_00010_0000000000001010 -> Hex: 32'h2802_000A
        dut.Mem[1] = 32'h2802_000A;

        // --- NOPs INSerted to Resolve Data Hazard ---
        // NOP 1: ADD R0, R0, R0
        dut.Mem[2] = 32'h0000_0000;
        
        // NOP 2: ADD R0, R0, R0
        // These delay the pipeline enough for ADDI to reach Write-Back
        dut.Mem[3] = 32'h0000_0000;

        // Instruction 3: ADD R3, R1, R2  (Opcode: 0, rs: 1, rt: 2, rd: 3)
        // Binary: 000000_00001_00010_00011_00000000000 -> Hex: 32'h0022_1800
        dut.Mem[4] = 32'h0022_1800;

        // Instruction 4: HLT (Opcode: 63)
        // Binary: 111111_00000_00000_00000_00000000000 -> Hex: 32'hFC00_0000
        dut.Mem[5] = 32'hFC00_0000;

        // Monitor the PC and specific registers as the simulation runs
        $monitor("Time: %0t | PC: %0d | R1: %0d | R2: %0d | R3: %0d", 
                 $time, dut.PC, dut.Reg[1], dut.Reg[2], dut.Reg[3]);

        // Wait until the processor asserts the 'halted' flag
        wait (dut.halted == 1'b1);

        // Allow one extra cycle for the final Write-Back stage to finish
        #20;

        // Print final results
        $display("\n========================================");
        $display("   Pipeline Execution Completed");
        $display("========================================");
        $display("Final Register States:");
        $display("R1 = %0d (Expected: 5)", dut.Reg[1]);
        $display("R2 = %0d (Expected: 10)", dut.Reg[2]);
        $display("R3 = %0d (Expected: 15)", dut.Reg[3]);
        $display("========================================");

        // End simulation
        $finish;
    end

    initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, mips32_tb);
    end

endmodule