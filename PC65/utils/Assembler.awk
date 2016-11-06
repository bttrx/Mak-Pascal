BEGIN {
    op_file = ARGV[1]       # Opcode file
    srcfile = ARGV[2]       # Source file
    ARGV[2] = ""            # Any other argument list files are data files
    
    split(srcfile, fn_ext, ".")
    tmpfile = fn_ext[1] ".p01"      # Temporary file
    outfile = fn_ext[1] ".out"      # Output file

    printf("\n\n----------------------------------------------------------\n\n")
    printf("%-s => %-s : %-s => %-s", srcfile, fn_ext[1], fn_ext[2], tmpfile)
    printf("\n")
    printf("%-s => %-s : %-s => %-s", srcfile, fn_ext[1], fn_ext[2], outfile)
    printf("\n\n----------------------------------------------------------\n\n")
    printf("Opcode Table")
    printf("\n\n----------------------------------------------------------\n\n")
    while(getline <op_file > 0) {
        op_len[$1] = $3 + $4        # Total length - instruction + data lengths
        dt_len[$1] = $4             # Data Length
        opcode[$1] = $5             # Instruction (prefix + opcode)
        
        printf("%-12s: %-12s %2d %2d\n", $1, opcode[$1], op_len[$1], dt_len[$1])
    }
    close(op_file)          # Close opcode file

    # Conditional/Unconditional 8/16-bit PC-relative Branch/Jump Instructions
	
	branch["bra"] = 2;  jump["jra"] = 4     # branch/jump relative always
	branch["beq"] = 2;  jump["jeq"] = 3     # branch/jump relative if( Z)
	branch["bne"] = 2;  jump["jne"] = 3     # branch/jump relative if(!Z)
	branch["bgt"] = 3;  jump["jgt"] = 4     # branch/jump relative if()
	branch["bge"] = 3;  jump["jge"] = 4     # branch/jump relative if()
	branch["blt"] = 3;  jump["jlt"] = 4     # branch/jump relative if()
	branch["ble"] = 3;  jump["jle"] = 4     # branch/jump relative if()

    # Set field separator: one or more spaces or tabs
    
    FS = "[ \t]+"           

    # Assembler Pass 1
    
    printf("\n\n----------------------------------------------------------\n\n")
    printf("Assembler Pass 1")    
    printf("\n\n----------------------------------------------------------\n\n")
    
    nextmem = 0

    while(getline <srcfile > 0) {
        sub(/;.*/, "")          # strip comments from the input line
        lbl = $1; op = $2; dt = $3
        if(lbl == "") {
            if((op !~ /^[\._]{1}/) && (op != "")) {
	            if(dt == "") {
	                op = op "_imp"
	            } else if(dt ~ /^[aA]$/) { 
	                op = op "_A"
	                dt = ""
	            } else if(dt ~ /^[xX]$/) { 
	                op = op "_X"
	                dt = ""
	            } else if(dt ~ /^[yY]$/) { 
	                op = op "_Y"
	                dt = ""
	            } else if((dt ~ /^[#]/) && ($2 ~ /[wW]$/)) { 
	                op = op "_imm16"
	                dt = substr(dt, 2)
	            } else if(dt ~ /^[#]/) { 
	                op = op "_imm"
	                dt = substr(dt, 2)
	            } else if(dt ~ /,[sS]$/) { 
	                op = op "_sp"
	                split(dt, operand, ",")
	                dt = operand[1]
	            } else if(dt ~ /,[sS])$/) { 
	                op = op "_spI"
	                split(dt, operand, ",")
	                dt = substr(operand[1], 2)
	            } else if(dt ~ /,[sS]),[yY]$/) { 
	                op = op "_spIY"
	                split(dt, operand, ",")
	                dt = substr(operand[1], 2)
	            } else if(dt ~ /,[bB]$/) { 
	                op = op "_bp"
	                split(dt, operand, ",")
	                dt = operand[1]
	            } else if(dt ~ /,[bB])$/) { 
	                op = op "_bpI"
	                split(dt, operand, ",")
	                dt = substr(operand[1], 2)
	            } else if(dt ~ /,[bB]),[yY]$/) { 
	                op = op "_bpIY"
	                split(dt, operand, ",")
	                dt = substr(operand[1], 2)
	            } else if(op in branch) { 
	                op = op "_rel"
	            } else if(op in jump) { 
	                op = op "_rel16"
	            } else if(op == "jmp") { 
	                op = op "_abs"
	            } else if(op == "jsr") { 
	                op = op "_abs"
	            } else if(dt ~ /_[0-9]{3}\+2$/) { 
	                op = op "_abs"
	            } else if(dt ~ /_[0-9]{3}$/) { 
	                op = op "_abs"
	            } else { 
	                op = "XXX---ERROR"
	                dt = ""
                }
                print op "\t" dt > tmpfile
                printf("%04X: %-11s\t%-s\n", nextmem, op, dt)
                
                nextmem += op_len[op]
            }
        } else {
            symtab[lbl] = nextmem
            memtab[nextmem] = lbl

            if(op == ".ORG") {                  #define memory start address
                nextmem = dt
            } else if(op == ".EQ") {            #define constants
                symtab[lbl] = dt
            } else if(op == ".DB") {            #define variables
                nextmem += dt
            } else if(op == ".DD") {            #define float literals
                nextmem += 4
            } else if(dt == ".DS") {            #define string literals
                split($0, string, "\"")
                nextmem += length(string[2])
            }
        }
    }
    close(tmpfile)

    printf("\n\n----------------------------------------------------------\n\n")
    printf("Assembler Symbol Table")    
    printf("\n\n----------------------------------------------------------\n\n")
    
    for(i in symtab) {
        if(symtab[i] < 0) symtab[i] += 65536
        printf("%-20s => %04X => %-20s\n", i, symtab[i], memtab[symtab[i]])
    }
    
    # Assembler Pass 2
    
    printf("\n\n----------------------------------------------------------\n\n")
    printf("Assembler Pass 2")    
    printf("\n\n----------------------------------------------------------\n\n")
    
    nextmem = 0
    while(getline <tmpfile > 0) {
        op = $1; dt = $2
        
        split(op, instruction_operand, "_")
        op_code = instruction_operand[1]
        addr_md = instruction_operand[2]
        
        # Compute operand value
        
        op_val = -1
        if(dt in symtab) {                  # Insert symbol value
            op_val = symtab[dt]
        } else if(dt ~ /^[-\+]?[0-9]+$/) {  # Insert numeric literal value
            op_val = dt
        }
        
        # For PC-relative instructions, convert adresses into relative offsets 
        
        if((op_code in branch) || (op_code in jump)) {
            op_val = op_val - (nextmem + op_len[op])  
        }
        
        # Convert operand values into 8-bit/16-bit unsigned values
        
        if(op_val < 0) op_val += 65536
        if(op_val < 0) op_val  = 65535
        
        lo = (op_val % 256)
        hi = (op_val / 256) % 256
        
        # Form the hexadecimal representation of the instruction

        len = dt_len[op]
        if(len == 1) {
            instruction = sprintf("%s%02X", opcode[op], lo)
        } else if(len == 2) {
            instruction = sprintf("%s%02X%02X", opcode[op], lo, hi)
        } else {
            instruction = sprintf("%s", opcode[op])
        }
        
        # Add labels back to the output

        if((nextmem in memtab) && (memtab[nextmem] != "")) {
            printf("\t\t\t\t\t; %s\n", memtab[nextmem])
            printf("\t\t\t\t\t; %s\n", memtab[nextmem]) > outfile
        }
        
        # Output the hexadecial representation of the instruction

        printf("%04X: %-8s", nextmem, instruction)
        printf("%04X: %-8s", nextmem, instruction) > outfile
        
        # Output intermediate representation with substitution of duplicate
        #   symbols pointing to common memory locations
        
        if((dt in symtab) && (memtab[symtab[dt]] != "")) {
            printf("\t\t;\t\t\t%-11s\t%-s\n", op, memtab[symtab[dt]])
            printf("\t\t;\t\t\t%-11s\t%-s\n", op, memtab[symtab[dt]]) > outfile
        } else {
            printf("\t\t;\t\t\t%-11s\t%-s\n", op, dt)
            printf("\t\t;\t\t\t%-11s\t%-s\n", op, dt) > outfile
        }

        # Advance the memory pointer by the instruction length

        nextmem += op_len[op]
    }
    close(tmpfile)
    close(outfile)
}

