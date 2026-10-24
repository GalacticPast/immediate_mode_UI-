// A tiny register machine for the debugger demo: 8 registers, 256 bytes of memory,
// a stack at the top of memory, and a program that never stops changing things.
package main

import "core:fmt"

Reg :: enum u8 { R0, R1, R2, R3, R4, R5, R6, R7 }

Op :: enum u8 {
    Nop, Li, Mov, Add, Addi, Sub, Mul, Mod, Cmp, Cmpi,
    Jmp, Jz, Jnz, Jlt, Jge, Ld, St, Push, Pop, Call, Ret, Out, Halt,
}

Instr :: struct {
    op:     Op,
    a, b:   Reg,
    imm:    i32,
    target: string, // jump or call label, resolved into imm
}

VM_Flag :: enum { Zero, Negative }

// What an Out instruction is reporting, for the output console.
Channel :: enum u8 { Prime, Fib, Pass }

Output_Line :: struct {
    channel: Channel,
    value:   i32,
    cycle:   u64,
}

HISTORY :: 240
STACK_BASE :: 0x100 // the stack grows down from the end of memory
OUTPUT_LIMIT :: 400

VM :: struct {
    regs:           [Reg]i32,
    pc, sp:         i32,
    flags:          bit_set[VM_Flag],
    halted:         bool,
    cycles:         u64,
    mem:            [256]u8,
    // when each cell and register last changed, in seconds, so the view can fade highlights
    mem_write_time: [256]f64,
    reg_write_time: [Reg]f64,
    output:         [dynamic]Output_Line,
    output_total:   int,
    history:        [HISTORY]i32,
    history_head:   int,
    history_count:  int,
}

Program :: struct {
    code:    [dynamic]Instr,
    labels:  map[int]string, // address -> label, for the disassembly
    address: map[string]int, // label -> address
}

vm_reset :: proc(vm: ^VM) {
    output := vm.output
    clear(&output)
    vm^ = {sp = STACK_BASE, output = output}
}

vm_destroy :: proc(vm: ^VM) {
    delete(vm.output)
}

program_destroy :: proc(p: ^Program) {
    delete(p.code)
    delete(p.labels)
    delete(p.address)
}

@(private = "file")
label :: proc(p: ^Program, name: string) {
    p.labels[len(p.code)] = name
    p.address[name] = len(p.code)
}

@(private = "file")
emit :: proc(p: ^Program, op: Op, a := Reg.R0, b := Reg.R0, imm: i32 = 0, target := "") {
    append(&p.code, Instr{op, a, b, imm, target})
}

// The demo program. Three routines run in a loop forever:
//   sieve   - marks primes below 128 in memory 0x00..0x7F and outputs each one
//   fib     - writes Fibonacci numbers (mod 256) into 0x80..0xBF
//   pattern - draws a moving ramp into 0xC0..0xEF, shifted by the pass counter in r7
program_build :: proc(p: ^Program) {
    label(p, "main")
    emit(p, .Call, target = "sieve")
    emit(p, .Call, target = "fib")
    emit(p, .Call, target = "pattern")
    emit(p, .Addi, .R7, imm = 1)
    emit(p, .Out, .R7, imm = i32(Channel.Pass))
    emit(p, .Jmp, target = "main")

    label(p, "sieve")
    emit(p, .Li, .R0, imm = 2)
    label(p, "sieve_fill")
    emit(p, .Li, .R1, imm = 1)
    emit(p, .St, .R1, .R0) // mem[r0] = 1: assume prime
    emit(p, .Addi, .R0, imm = 1)
    emit(p, .Cmpi, .R0, imm = 128)
    emit(p, .Jlt, target = "sieve_fill")
    emit(p, .Li, .R0, imm = 2)
    label(p, "sieve_outer")
    emit(p, .Ld, .R1, .R0)
    emit(p, .Cmpi, .R1, imm = 0)
    emit(p, .Jz, target = "sieve_next")
    emit(p, .Out, .R0, imm = i32(Channel.Prime))
    emit(p, .Mov, .R2, .R0)
    emit(p, .Add, .R2, .R0) // first multiple: 2p
    label(p, "sieve_cross")
    emit(p, .Cmpi, .R2, imm = 128)
    emit(p, .Jge, target = "sieve_next")
    emit(p, .Li, .R3, imm = 0)
    emit(p, .St, .R3, .R2) // mem[r2] = 0: composite
    emit(p, .Add, .R2, .R0)
    emit(p, .Jmp, target = "sieve_cross")
    label(p, "sieve_next")
    emit(p, .Addi, .R0, imm = 1)
    emit(p, .Cmpi, .R0, imm = 128)
    emit(p, .Jlt, target = "sieve_outer")
    emit(p, .Ret)

    label(p, "fib")
    emit(p, .Li, .R0, imm = 0)
    emit(p, .Li, .R1, imm = 1)
    emit(p, .Li, .R4, imm = 0x80)
    label(p, "fib_loop")
    emit(p, .St, .R0, .R4)
    emit(p, .Cmpi, .R4, imm = 0x8C)
    emit(p, .Jge, target = "fib_quiet") // only the first terms are interesting to print
    emit(p, .Out, .R0, imm = i32(Channel.Fib))
    label(p, "fib_quiet")
    emit(p, .Mov, .R2, .R0)
    emit(p, .Add, .R2, .R1)
    emit(p, .Mov, .R0, .R1)
    emit(p, .Mov, .R1, .R2)
    emit(p, .Push, .R0) // push and pop to give the stack view something to show
    emit(p, .Pop, .R5)
    emit(p, .Addi, .R4, imm = 1)
    emit(p, .Cmpi, .R4, imm = 0xC0)
    emit(p, .Jlt, target = "fib_loop")
    emit(p, .Ret)

    label(p, "pattern")
    emit(p, .Li, .R0, imm = 0xC0)
    label(p, "pattern_loop")
    emit(p, .Mov, .R1, .R0)
    emit(p, .Add, .R1, .R7)
    emit(p, .Li, .R3, imm = 48)
    emit(p, .Mod, .R1, .R3)
    emit(p, .Li, .R3, imm = 5)
    emit(p, .Mul, .R1, .R3)
    emit(p, .St, .R1, .R0)
    emit(p, .Addi, .R0, imm = 1)
    emit(p, .Cmpi, .R0, imm = 0xF0)
    emit(p, .Jlt, target = "pattern_loop")
    emit(p, .Ret)

    for &ins in p.code {
        if ins.target != "" do ins.imm = i32(p.address[ins.target])
    }
}

@(private = "file")
set_reg :: proc(vm: ^VM, r: Reg, v: i32, now: f64) {
    vm.regs[r] = v
    vm.reg_write_time[r] = now
}

@(private = "file")
store :: proc(vm: ^VM, addr: i32, v: i32, now: f64) {
    a := u8(addr & 0xff)
    vm.mem[a] = u8(v & 0xff)
    vm.mem_write_time[a] = now
}

// Runs one instruction. now is the wall-clock time, used only for highlights.
vm_step :: proc(vm: ^VM, p: ^Program, now: f64, plot_reg: Reg) {
    if vm.halted do return
    if vm.pc < 0 || int(vm.pc) >= len(p.code) {
        vm.halted = true
        return
    }
    ins := p.code[vm.pc]
    next := vm.pc + 1
    a, b := vm.regs[ins.a], vm.regs[ins.b]
    compare :: proc(vm: ^VM, x, y: i32) {
        vm.flags = {}
        if x == y do vm.flags += {.Zero}
        if x < y do vm.flags += {.Negative}
    }
    switch ins.op {
        case .Nop:
        case .Li: set_reg(vm, ins.a, ins.imm, now)
        case .Mov: set_reg(vm, ins.a, b, now)
        case .Add: set_reg(vm, ins.a, a + b, now)
        case .Addi: set_reg(vm, ins.a, a + ins.imm, now)
        case .Sub: set_reg(vm, ins.a, a - b, now)
        case .Mul: set_reg(vm, ins.a, a * b, now)
        case .Mod: set_reg(vm, ins.a, b == 0 ? 0 : a %% b, now)
        case .Cmp: compare(vm, a, b)
        case .Cmpi: compare(vm, a, ins.imm)
        case .Jmp: next = ins.imm
        case .Jz: if .Zero in vm.flags do next = ins.imm
        case .Jnz: if .Zero not_in vm.flags do next = ins.imm
        case .Jlt: if .Negative in vm.flags do next = ins.imm
        case .Jge: if .Negative not_in vm.flags do next = ins.imm
        case .Ld: set_reg(vm, ins.a, i32(vm.mem[u8(b & 0xff)]), now)
        case .St: store(vm, b, a, now)
        case .Push:
            vm.sp -= 1
            store(vm, vm.sp, a, now)
        case .Pop:
            set_reg(vm, ins.a, i32(vm.mem[u8(vm.sp & 0xff)]), now)
            vm.sp += 1
        case .Call:
            vm.sp -= 1
            store(vm, vm.sp, next, now)
            next = ins.imm
        case .Ret:
            next = i32(vm.mem[u8(vm.sp & 0xff)])
            vm.sp += 1
        case .Out:
            if len(vm.output) >= OUTPUT_LIMIT do ordered_remove(&vm.output, 0)
            append(&vm.output, Output_Line{Channel(ins.imm), a, vm.cycles})
            vm.output_total += 1
        case .Halt:
            vm.halted = true
            next = vm.pc
    }
    vm.pc = next
    vm.cycles += 1
    vm.history[vm.history_head] = vm.regs[plot_reg]
    vm.history_head = (vm.history_head + 1) % HISTORY
    vm.history_count = min(vm.history_count + 1, HISTORY)
}

// "add r2, r0", "jlt sieve_fill", ... for the disassembly view.
disassemble :: proc(ins: Instr, buf: []u8) -> string {
    names := [Op]string {
        .Nop = "nop", .Li = "li", .Mov = "mov", .Add = "add", .Addi = "addi", .Sub = "sub",
        .Mul = "mul", .Mod = "mod", .Cmp = "cmp", .Cmpi = "cmpi", .Jmp = "jmp", .Jz = "jz",
        .Jnz = "jnz", .Jlt = "jlt", .Jge = "jge", .Ld = "ld", .St = "st", .Push = "push",
        .Pop = "pop", .Call = "call", .Ret = "ret", .Out = "out", .Halt = "halt",
    }
    regs := [Reg]string{.R0 = "r0", .R1 = "r1", .R2 = "r2", .R3 = "r3", .R4 = "r4", .R5 = "r5", .R6 = "r6", .R7 = "r7"}
    n := names[ins.op]
    switch ins.op {
        case .Nop, .Ret, .Halt: return n
        case .Li, .Addi, .Cmpi: return fmt.bprintf(buf, "%-5s %s, %d", n, regs[ins.a], ins.imm)
        case .Mov, .Add, .Sub, .Mul, .Mod, .Cmp: return fmt.bprintf(buf, "%-5s %s, %s", n, regs[ins.a], regs[ins.b])
        case .Jmp, .Jz, .Jnz, .Jlt, .Jge, .Call: return fmt.bprintf(buf, "%-5s %s", n, ins.target)
        case .Ld: return fmt.bprintf(buf, "%-5s %s, [%s]", n, regs[ins.a], regs[ins.b])
        case .St: return fmt.bprintf(buf, "%-5s [%s], %s", n, regs[ins.b], regs[ins.a])
        case .Push, .Pop: return fmt.bprintf(buf, "%-5s %s", n, regs[ins.a])
        case .Out: return fmt.bprintf(buf, "%-5s %s, %v", n, regs[ins.a], Channel(ins.imm))
    }
    return n
}
