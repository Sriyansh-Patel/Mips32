`timescale 1ns/1ps

module mips32(
    input clk1,
    input clk2
);

    //-----------------------------
    // Program Counter
    //-----------------------------
    reg [31:0] PC;

    //-----------------------------
    // IF/ID Pipeline Registers
    //-----------------------------
    reg [31:0] IF_ID_IR;
    reg [31:0] IF_ID_NPC;

    //-----------------------------
    // ID/EX Pipeline Registers
    //-----------------------------
    reg [31:0] ID_EX_IR;
    reg [31:0] ID_EX_NPC;
    reg [31:0] ID_EX_A;
    reg [31:0] ID_EX_B;
    reg [31:0] ID_EX_IMM;
    reg [2:0]  ID_EX_type;

    //-----------------------------
    // EX/MEM Pipeline Registers
    //-----------------------------
    reg [31:0] EX_MEM_IR;
    reg [31:0] EX_MEM_ALUOut;
    reg [31:0] EX_MEM_B;
    reg [2:0]  EX_MEM_type;
    reg        EX_MEM_cond;

    //-----------------------------
    // MEM/WB Pipeline Registers
    //-----------------------------
    reg [31:0] MEM_WB_IR;
    reg [31:0] MEM_WB_ALUOut;
    reg [31:0] MEM_WB_LMD;
    reg [2:0]  MEM_WB_type;

    //-----------------------------
    // Register File
    //-----------------------------
    reg [31:0] Reg [0:31];

    //-----------------------------
    // Main Memory
    //-----------------------------
    reg [31:0] Mem [0:1023];

    //-----------------------------
    // Instruction Types
    //-----------------------------
    parameter RR_ALU = 3'b000,
              RM_ALU = 3'b001,
              LOAD   = 3'b010,
              STORE  = 3'b011,
              BRANCH = 3'b100,
              HALT   = 3'b101;

    //-----------------------------
    // Opcodes
    //-----------------------------
    parameter ADD   = 6'b000000,
              SUB   = 6'b000001,
              ANDD  = 6'b000010,
              ORR   = 6'b000011,
              SLT   = 6'b000100,
              MUL   = 6'b000101,

              HLT   = 6'b111111,

              LW    = 6'b001000,
              SW    = 6'b001001,

              ADDI  = 6'b001010,
              SUBI  = 6'b001011,
              SLTI  = 6'b001100,

              BNEQZ = 6'b001101,
              BEQZ  = 6'b001110;
              
    reg halted;
    reg taken_branch;

    integer i;

    initial
    begin
        PC = 0;
        halted = 0;
        taken_branch = 0;

        IF_ID_IR = 0;
        IF_ID_NPC = 0;

        ID_EX_IR = 0;
        ID_EX_NPC = 0;
        ID_EX_A = 0;
        ID_EX_B = 0;
        ID_EX_IMM = 0;
        ID_EX_type = 0;

        EX_MEM_IR = 0;
        EX_MEM_ALUOut = 0;
        EX_MEM_B = 0;
        EX_MEM_type = 0;
        EX_MEM_cond = 0;

        MEM_WB_IR = 0;
        MEM_WB_ALUOut = 0;
        MEM_WB_LMD = 0;
        MEM_WB_type = 0;

        for(i = 0; i < 32; i = i + 1)
            Reg[i] = 0;

        for(i = 0; i < 1024; i = i + 1)
            Mem[i] = 0;
    end

    //---------------------------------------------------------
    // 1. INSTRUCTION FETCH (IF) STAGE
    //---------------------------------------------------------
    always @(posedge clk1)
    begin
        if (!halted)
        begin
            // Branch taken by the instruction currently in EX/MEM
            if (((EX_MEM_IR[31:26] == BEQZ)  && EX_MEM_cond) ||
                ((EX_MEM_IR[31:26] == BNEQZ) && !EX_MEM_cond))
            begin
                // Fetch first instruction from branch target
                IF_ID_IR  <= #2 Mem[EX_MEM_ALUOut];
                IF_ID_NPC <= #2 EX_MEM_ALUOut + 1;

                // Update PC to next sequential instruction
                PC <= #2 EX_MEM_ALUOut + 1;

                // Inform later stages to squash the wrong-path instruction
                taken_branch <= #2 1'b1;
            end
            else
            begin
                // Normal sequential fetch
                IF_ID_IR  <= #2 Mem[PC];
                IF_ID_NPC <= #2 PC + 1;

                // Increment PC
                PC <= #2 PC + 1;
                
                // Clear the branch flag so normal execution resumes after squashing
                taken_branch <= #2 1'b0;
            end
        end
    end

    //---------------------------------------------------------
    // 2. INSTRUCTION DECODE (ID) STAGE
    //---------------------------------------------------------
    always @(posedge clk2)
    begin
        if (!halted)
        begin
            if(IF_ID_IR[25:21] == 0)
                ID_EX_A <= #2 0;
            else
                ID_EX_A <= #2 Reg[IF_ID_IR[25:21]];

            if(IF_ID_IR[20:16] == 0)
                ID_EX_B <= #2 0;
            else
                ID_EX_B <= #2 Reg[IF_ID_IR[20:16]];

            ID_EX_NPC <= #2 IF_ID_NPC;
            ID_EX_IR  <= #2 IF_ID_IR;

            ID_EX_IMM <= #2 {{16{IF_ID_IR[15]}}, IF_ID_IR[15:0]};

            case(IF_ID_IR[31:26])
                ADD, SUB, ANDD, ORR, SLT, MUL:
                    ID_EX_type <= #2 RR_ALU;

                ADDI, SUBI, SLTI:
                    ID_EX_type <= #2 RM_ALU;

                LW:
                    ID_EX_type <= #2 LOAD;

                SW:
                    ID_EX_type <= #2 STORE;

                BEQZ, BNEQZ:
                    ID_EX_type <= #2 BRANCH;

                HLT:
                    ID_EX_type <= #2 HALT;

                default:
                    ID_EX_type <= #2 HALT;
            endcase
        end
    end

    //---------------------------------------------------------
    // 3. EXECUTION (EX) STAGE
    //---------------------------------------------------------
    always @(posedge clk1)
    begin
        if (!halted)
        begin
            // Pipeline Register Transfer
            EX_MEM_type <= #2 ID_EX_type;
            EX_MEM_IR   <= #2 ID_EX_IR;

            case (ID_EX_type)

            //-------------------------------------------------
            // Register-Register ALU Instructions
            //-------------------------------------------------
            RR_ALU:
            begin
                case (ID_EX_IR[31:26])
                    ADD:  EX_MEM_ALUOut <= #2 ID_EX_A + ID_EX_B;
                    SUB:  EX_MEM_ALUOut <= #2 ID_EX_A - ID_EX_B;
                    ANDD: EX_MEM_ALUOut <= #2 ID_EX_A & ID_EX_B;
                    ORR:  EX_MEM_ALUOut <= #2 ID_EX_A | ID_EX_B;
                    // Fixed: Used $signed() for accurate signed magnitude comparison
                    SLT:  EX_MEM_ALUOut <= #2 ($signed(ID_EX_A) < $signed(ID_EX_B)) ? 32'd1 : 32'd0;
                    MUL:  EX_MEM_ALUOut <= #2 ID_EX_A * ID_EX_B;
                    default: EX_MEM_ALUOut <= #2 32'd0;
                endcase
            end

            //-------------------------------------------------
            // Register-Immediate ALU Instructions
            //-------------------------------------------------
            RM_ALU:
            begin
                case (ID_EX_IR[31:26])
                    ADDI: EX_MEM_ALUOut <= #2 ID_EX_A + ID_EX_IMM;
                    SUBI: EX_MEM_ALUOut <= #2 ID_EX_A - ID_EX_IMM;
                    // Fixed: Used $signed() for accurate signed magnitude comparison
                    SLTI: EX_MEM_ALUOut <= #2 ($signed(ID_EX_A) < $signed(ID_EX_IMM)) ? 32'd1 : 32'd0;
                    default: EX_MEM_ALUOut <= #2 32'd0;
                endcase
            end

            //-------------------------------------------------
            // LOAD / STORE
            //-------------------------------------------------
            LOAD, STORE:
            begin
                EX_MEM_ALUOut <= #2 ID_EX_A + ID_EX_IMM;
                EX_MEM_B      <= #2 ID_EX_B;
            end

            //-------------------------------------------------
            // BRANCH
            //-------------------------------------------------
            BRANCH:
            begin
                // Compute branch target
                EX_MEM_ALUOut <= #2 ID_EX_NPC + ID_EX_IMM;
                // Branch condition (BEQZ/BNEQZ)
                EX_MEM_cond <= #2 (ID_EX_A == 32'd0);
            end

            //-------------------------------------------------
            // HALT
            //-------------------------------------------------
            HALT:
            begin
                EX_MEM_ALUOut <= #2 32'd0;
            end

            //-------------------------------------------------
            // Invalid Instruction
            //-------------------------------------------------
            default:
            begin
                EX_MEM_ALUOut <= #2 32'd0;
            end
            endcase
        end
    end

    //---------------------------------------------------------
    // 4. MEMORY ACCESS (MEM) STAGE
    //---------------------------------------------------------
    always @(posedge clk2)
    begin
        if (!halted)
        begin
            // Pass pipeline registers to WB stage
            MEM_WB_type   <= #2 EX_MEM_type;
            MEM_WB_IR     <= #2 EX_MEM_IR;
            MEM_WB_ALUOut <= #2 EX_MEM_ALUOut;

            case (EX_MEM_type)
            RR_ALU, RM_ALU:
            begin
                // No memory operation required
            end
            
            LOAD:
            begin
                MEM_WB_LMD <= #2 Mem[EX_MEM_ALUOut];
            end
            
            STORE:
            begin
                if (!taken_branch)
                    Mem[EX_MEM_ALUOut] <= #2 EX_MEM_B;
            end
            
            BRANCH, HALT:
            begin
            end
            default:
            begin
                // Nothing to access in memory
            end
            endcase
        end
    end

    //---------------------------------------------------------
    // 5. WRITE BACK (WB) STAGE
    //---------------------------------------------------------
    always @(posedge clk1)
    begin
        if(!taken_branch)
        begin
            case(MEM_WB_type)
            RR_ALU:
            begin
                if(MEM_WB_IR[15:11] != 0)
                    Reg[MEM_WB_IR[15:11]] <= #2 MEM_WB_ALUOut;
            end

            RM_ALU:
            begin
                if(MEM_WB_IR[20:16] != 0)
                    Reg[MEM_WB_IR[20:16]] <= #2 MEM_WB_ALUOut;
            end

            LOAD:
            begin
                if(MEM_WB_IR[20:16] != 0)
                    Reg[MEM_WB_IR[20:16]] <= #2 MEM_WB_LMD;
            end

            HALT:
            begin
                halted <= #2 1'b1;
            end
            endcase
        end
    end

endmodule