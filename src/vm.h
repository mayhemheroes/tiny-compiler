#ifndef VM_H
#define VM_H

#include <stdio.h>

#include "stack.h"
#include "sym.h"
#include "asm.h"
#include "defs.h"

#define POP_BOTH arg2 = pop(); arg1 = pop()

byte *cur_opcode;

byte next_opcode()
{
    return *cur_opcode++;
}

void run(byte *bytecode)
{
    int arg1, arg2;

    cur_opcode = bytecode;

    next_op:
    switch (next_opcode()) {
        case PUSH: push(next_opcode()); goto next_op;
        case READ: push(get_sym(next_opcode())->val); goto next_op;
        case WRITE: set_sym(next_opcode(), pop()); goto next_op;
        case ADD: POP_BOTH; push(arg1 + arg2); goto next_op;
        case SUB: POP_BOTH; push(arg1 - arg2); goto next_op;
        case MUL: POP_BOTH; push(arg1 * arg2); goto next_op;
        case DIV: POP_BOTH; push(arg1 / arg2); goto next_op;
        case RET: {
            int i;
            for (i = 0; i < get_table_size(); i++) {
                printf("%s = %i\n", get_sym(i)->name, get_sym(i)->val);
            }

            return;
        }
    }
}

#endif