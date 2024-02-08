const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const r = @cImport(@cInclude("raylib.h"));

const font = @import("font.zig");

const SHIFT_WITH_MOV: bool = false;
const CLASSIC_BNNN_BEHAVIOUR: bool = false;
const SCALE_MULTIPLIER = 10;
const STEP_MODE: bool = false;
const AMIGA_FX1E_BEHAVIOUR: bool = true;
const OLD_STORE_LOAD_BEHAVIOUR: bool = false;

const KEY_CONFIG_ONE: [0x10]u8 = .{ // key mapping from guide
    r.KEY_ONE, r.KEY_TWO, r.KEY_THREE, r.KEY_FOUR, // 1, 2, 3, 4
    r.KEY_Q, r.KEY_W, r.KEY_E, r.KEY_R, // Q, W, E, R
    r.KEY_A, r.KEY_S, r.KEY_D, r.KEY_F, // A, S, D, F
    r.KEY_Z, r.KEY_X, r.KEY_C, r.KEY_V, // Z, X, C, V
};

const Chip8State = struct {
    V: [16]u8,
    I: u16,
    SP: u16,
    PC: u16,
    delay: u8,
    sound: u8,
    memory: [4096]u8,
    screen: [64 * 32]u8,
    stack: [16]u16,
    const Self = @This();

    pub fn getOp(self: *Self) struct { AB: u8, CD: u8 } {
        return .{ .AB = self.memory[self.PC], .CD = self.memory[self.PC + 1] };
    }

    pub fn push(self: *Self, val: u16) void {
        self.stack[self.SP + 1] = val;
        self.SP += 1;
    }

    pub fn pop(self: *Self) u16 {
        const val = self.stack[self.SP];
        self.stack[self.SP] = 0;
        self.SP -= 1;

        return val;
    }
};

pub fn main() !void {
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    var chip8state: Chip8State = Chip8State{
        .V = .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
        .I = 0,
        .SP = 0,
        .PC = 0x200,
        .delay = 0,
        .sound = 0,
        .memory = init: {
            var initial: [4096]u8 = undefined;
            @memset(&initial, 0);
            break :init initial;
        },
        .screen = init: {
            var initial: [64 * 32]u8 = undefined;
            @memset(&initial, 0);
            break :init initial;
        },
        .stack = .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    };

    // load 4x5 font into beginning of memory
    @memcpy(chip8state.memory[0..80], &font.font4x5);

    const fishieCh8 = try std.fs.cwd().readFile("Fishie.ch8", chip8state.memory[0x200..]);
    _ = fishieCh8; // autofix

    //const testy = try std.fs.cwd().readFile("test_opcode.ch8", chip8state.memory[0x200..]);
    //_ = testy; // autofix

    std.debug.print("{x}", .{chip8state.memory});

    //var pc: u16 = 0x200;
    //while (pc < (fishieCh8.len + 0x200)) : (pc += 2) {
    //    try dissasembleChip8Op(&chip8state.memory, pc);
    //}

    r.InitWindow(64 * SCALE_MULTIPLIER, 32 * SCALE_MULTIPLIER, "New Window");
    r.SetTargetFPS(60);
    defer r.CloseWindow();

    r.BeginDrawing();
    r.DrawCircle(50, 50, 50, r.BLUE);
    r.EndDrawing();

    while (!r.WindowShouldClose()) {
        if (chip8state.delay != 0) {
            chip8state.delay -= 1;
        }

        if (chip8state.sound != 0) {
            chip8state.sound -= 1;
        }

        if (r.IsKeyPressed(r.KEY_SPACE) or !STEP_MODE) {
            //std.debug.print("DOING SOMETHING!\n", .{});
            try processChip8Op(&chip8state);
        }

        r.BeginDrawing();

        for (0..32) |y| {
            for (0..64) |x| {
                const position = x + (y * 32);
                const screen_x: c_int = @intCast(x * SCALE_MULTIPLIER);
                const screen_y: c_int = @intCast(y * SCALE_MULTIPLIER);
                const screen_size: c_int = @intCast(SCALE_MULTIPLIER);
                if (chip8state.screen[position] == 0b10000000) {
                    r.DrawRectangle(screen_x, screen_y, screen_size, screen_size, r.WHITE);
                } else {
                    r.DrawRectangle(screen_x, screen_y, screen_size, screen_size, r.BLACK);
                }
            }
        }

        r.EndDrawing();
    }

    std.debug.print("{x}", .{chip8state.memory});
}

fn processChip8Op(state: *Chip8State) !void {
    const out = std.io.getStdOut();
    var buf = std.io.bufferedWriter(out.writer());
    var w = buf.writer();

    const op = state.getOp(); // 2 bytes
    const AB = op.AB;
    const CD = op.CD;
    const A = AB >> 4; // broken into nibs for handling
    const B = AB & 0xf;
    const C = CD >> 4;
    const D = CD & 0xf;

    try w.print("{x:0>4}", .{state.PC});

    state.PC += 2;

    switch (A) {
        0x0 => {
            switch (CD) {
                0xe0 => {
                    try w.print("{s:>10}\n", .{"CLS"});
                    @memset(state.screen[0..], 0);
                },
                0xee => {
                    try w.print("{s:>10}\n", .{"RTS"});
                    state.PC = state.pop();
                    try w.print("Popped {x:0>4}\n from stack\n", .{state.PC});
                    try w.print("Jumped to {x:0>4}\n", .{state.PC});
                },
                0x00 => try w.print("{s:>10}\n", .{"NOOP"}),
                else => try w.print(" UNKNOWN 0\n", .{}),
            }
        },
        0x1 => {
            try w.print("{s:>10} ${x:0>2}{x:0>2}\n", .{ "JUMP", B, CD });
            state.PC = (@as(u16, (0x00 | B)) << 0x8) | CD;
            try w.print("Jumped to {x:0>4}\n", .{state.PC});
        },
        0x2 => {
            try w.print("{s:>10} ${x:0>2}{x:0>2}\n", .{ "CALL", B, CD });
            state.push(state.PC);
            try w.print("Pushed {x:0>4}\n to stack\n", .{state.PC});
            state.PC = (@as(u16, (0x00 | B)) << 0x8) | CD;
            try w.print("Jumped to {x:0>4}\n", .{state.PC});
        },
        0x3 => {
            try w.print("{s:>10} V{x:0>2}, #${x:0>2}\n", .{ "SKIP.EQ", B, CD });
            if (state.V[B] == CD) {
                state.PC += 2;
                try w.print("Skipped instruction\n", .{});
            }
        },
        0x4 => {
            try w.print("{s:>10} V{x:0>2}, #${x:0>2}\n", .{ "SKIP.NE", B, CD });
            if (state.V[B] != CD) {
                state.PC += 2;
                try w.print("Skipped instruction\n", .{});
            }
        },
        0x5 => {
            try w.print("{s:>10} V{x:0>2}, V{x:0>2}\n", .{ "SKIP.EQ", B, C });
            if (state.V[B] == state.V[C]) {
                state.PC += 2;
                try w.print("Skipped instruction\n", .{});
            }
        },
        0x6 => {
            try w.print("{s:>10} V{x:0>2}, #${x:0>2}\n", .{ "MVI", B, CD });
            state.V[B] = CD;
            try w.print("V{x:0>2} is now {x:0>2}\n", .{ B, state.V[B] });
        },
        0x7 => {
            try w.print("{s:>10} V{x:0>2}, #${x:0>2}\n", .{ "ADI", B, CD });
            state.V[B] +%= CD;
            try w.print("V{x:0>2} is now {x:0>2}\n", .{ B, state.V[B] });
        },
        0x8 => {
            switch (D) {
                0x00 => {
                    try w.print("{s:>10} V{x:0>2}, V{x:0>2}\n", .{ "MOV", B, C });
                    state.V[B] = state.V[C];
                    try w.print("V{x:0>2} is now {x:0>2}\n", .{ B, state.V[B] });
                },
                0x01 => {
                    try w.print("{s:>10} V{x:0>2}, V{x:0>2}\n", .{ "OR", B, C });
                    state.V[B] |= state.V[C];
                    try w.print("V{x:0>2} is now {x:0>2}\n", .{ B, state.V[B] });
                },
                0x02 => {
                    try w.print("{s:>10} V{x:0>2}, V{x:0>2}\n", .{ "AND", B, C });
                    state.V[B] &= state.V[C];
                    try w.print("V{x:0>2} is now {x:0>2}\n", .{ B, state.V[B] });
                },
                0x03 => {
                    try w.print("{s:>10} V{x:0>2}, V{x:0>2}\n", .{ "XOR", B, C });
                    state.V[B] ^= state.V[C];
                    try w.print("V{x:0>2} is now {x:0>2}\n", .{ B, state.V[B] });
                },
                0x04 => {
                    try w.print("{s:>10} V{x:0>2}, V{x:0>2}\n", .{ "ADD", B, C });
                    // NEED FLAG SETTING HERE
                    state.V[B] +%= state.V[C];
                    try w.print("V{x:0>2} is now {x:0>2}\n", .{ B, state.V[B] });
                },
                0x05 => {
                    try w.print("{s:>10} V{x:0>2}, V{x:0>2}\n", .{ "SUB", B, C });
                    if (state.V[B] >= state.V[C]) {
                        state.V[0xf] = 1;
                    } else {
                        state.V[0xf] = 0;
                    }
                    state.V[B] -%= state.V[C];
                    try w.print("V{x:0>2} is now {x:0>2}\n", .{ B, state.V[B] });
                },
                0x06 => {
                    try w.print("{s:>10} V{x:0>2}, V{x:0>2}\n", .{ "SHR", B, C });
                    if (SHIFT_WITH_MOV) {
                        state.V[B] = state.V[C];
                    }
                    state.V[0xf] = state.V[B] & 0b00000001;
                    state.V[B] >>= 1;
                },
                0x07 => {
                    try w.print("{s:>10} V{x:0>2}, V{x:0>2}\n", .{ "SUBB", B, C });
                    if (state.V[C] >= state.V[B]) {
                        state.V[0xf] = 1;
                    } else {
                        state.V[0xf] = 0;
                    }
                    state.V[B] = state.V[C] -% state.V[B];
                    try w.print("V{x:0>2} is now {x:0>2}\n", .{ B, state.V[B] });
                },
                0x0e => {
                    try w.print("{s:>10} V{x:0>2}, V{x:0>2}\n", .{ "SHL", B, C });
                    if (SHIFT_WITH_MOV) {
                        state.V[B] = state.V[C];
                    }
                    state.V[0xf] = state.V[B] & 0b1000000;
                    state.V[B] <<= 1;
                },
                else => try w.print(" UNKNOWN 8\n", .{}),
            }
        },
        0x9 => {
            try w.print("{s:>10} V{x:0>2}, V{x:0>1}\n", .{ "SKIP.NE", B, C });
            if (state.V[B] != state.V[C]) {
                state.PC += 2;
                try w.print("Skipped instruction\n", .{});
            }
        },
        0xa => {
            try w.print("{s:>10} I  , #${x:01}{x:0>2}\n", .{ "MVI", B, CD });
            state.I = (@as(u16, (0x00 | B)) << 0x8) | CD;
            try w.print("I is now {x:0>2}\n", .{state.I});
        },
        0xb => {
            try w.print("{s:>10} ${x:0>1}{x:0>2}(V00)\n", .{ "JUMP", B, CD });
            if (CLASSIC_BNNN_BEHAVIOUR) { // should do
                state.PC = (@as(u16, (0x00 | B)) << 0x8) | CD;
                state.PC += state.V[0];
            } else { // weird
                state.PC = (@as(u16, (0x00 | B)) << 0x8) | CD;
                state.PC += state.V[B];
            }
        },
        0xc => {
            try w.print("{s:>10} V{x:0>2}, #${x:0>2}\n", .{ "RNDMSK", B, CD });
            var rand = std.rand.DefaultPrng.init(0);
            var num = rand.random().int(u8);
            num &= CD;
            state.V[B] = num;
        },
        0xd => { // HARD ONE
            try w.print("{s:>10} V{x:0>2}, V{x:0>2}, #${x:0>2}\n", .{ "SPRITE", B, C, D });
            const x: u8 = state.V[B] & 63; // get coords in screen space
            const y: u8 = state.V[C] & 31;

            state.V[B] = 0;

            for (0..D) |y_1| {
                const pixel_row = state.memory[state.I + y_1];
                for (0..8) |x_1| {
                    const pixel = (pixel_row << @intCast(x_1)) & 0b10000000;
                    const position = (x + x_1) + ((y + y_1) * 32);

                    const old = state.screen[position];

                    state.screen[position] ^= pixel; // screen positions either 0 or 0x10000000

                    if (old == 0b10000000 and state.screen[position] == 0) {
                        state.V[0xf] = 1;
                    }

                    if (((x + x_1 + 1) % 32) == 0) { // on very right hand edge
                        break;
                    }
                }
            }
        },
        0xe => {
            switch (CD) {
                0x9e => {
                    try w.print("{s:>10} V{x:0>2}\n", .{ "SKIP.KEY", B });
                    if (isKeyDown(B)) {
                        state.PC += 2;
                        try w.print("Skipped instruction\n", .{});
                    }
                },
                0xa1 => {
                    try w.print("{s:>10} V{x:0>2}\n", .{ "SKIP.NOKEY", B });
                    if (!isKeyDown(B)) {
                        state.PC += 2;
                        try w.print("Skipped instruction\n", .{});
                    }
                },
                else => try w.print(" UNKNOWN e\n", .{}),
            }
        },
        0xf => {
            switch (CD) {
                0x07 => {
                    try w.print("{s:>10} V{x:0>2}, DELAY\n", .{ "MOV", B });
                    state.V[B] = state.delay;
                    try w.print("V{x:0>2} is now {x:0>2}\n", .{ B, state.V[B] });
                },
                0x0a => {
                    try w.print("{s:>10} V{x:0>2}\n", .{ "WAITKEY", B });
                    const info = getDownKey();
                    if (!info.down) {
                        state.PC -= 2;
                        try w.print("Waiting\n", .{});
                    } else {
                        state.V[B] = info.key;
                    }
                },
                0x15 => {
                    try w.print("{s:>10} DELAY, V{x:0>2}\n", .{ "MOV", B });
                    state.delay = state.V[B];
                    try w.print("DELAY is now {x:0>2}\n", .{state.delay});
                },
                0x18 => {
                    try w.print("{s:>10} SOUND, V{x:0>2}\n", .{ "MOV", B });
                    state.sound = state.V[B];
                    try w.print("SOUND is now {x:0>2}\n", .{state.sound});
                },
                0x1e => {
                    try w.print("{s:>10} I, V{x:0>2}\n", .{ "ADD", B });
                    state.I += state.V[B];
                    try w.print("I is now {x:0>2}\n", .{state.I});
                    if (state.I > 0xFFF and AMIGA_FX1E_BEHAVIOUR) {
                        state.V[0xf] = 1; // weird amiga behaviour, doesnt hurt apparantly
                    }
                },
                0x29 => {
                    try w.print("{s:>10} V{x:0>2}\n", .{ "SPRITECHAR", B });
                    const character = state.V[B] & 0xf;
                    state.I = character * 5;
                    try w.print("I is now {x:0>2}\n", .{state.I});
                },
                0x33 => {
                    try w.print("{s:>10} V{x:0>2}\n", .{ "MOVBCD", B });
                    const hundreds: u8 = state.V[B] / 100;
                    const tens: u8 = (state.V[B] % 100) / 10;
                    const ones: u8 = state.V[B] % 10;

                    const number = [_]u8{ hundreds, tens, ones };

                    @memcpy(state.memory[state.I .. state.I + 3], &number);
                },
                0x55 => {
                    try w.print("{s:>10} (I), V0-V{x:0>2}, DELAY\n", .{ "MOVM", B });
                    if (OLD_STORE_LOAD_BEHAVIOUR) { // should add
                        try w.print("NOT IMPLEMENTED, THAT IS THE OLD WAS", .{});
                    }

                    @memcpy(state.memory[state.I .. state.I + B], state.V[0..B]);
                },
                0x65 => {
                    try w.print("{s:>10} V0-V{x:0>2}, (I)\n", .{ "MOVm", B });
                    if (OLD_STORE_LOAD_BEHAVIOUR) {
                        try w.print("NOT IMPLEMENTED, THAT IS THE OLD WAS", .{});
                    }

                    @memcpy(state.V[0..B], state.memory[state.I .. state.I + B]);
                },
                else => try w.print(" UNKNOWN f\n", .{}),
            }
        },
        else => try w.print(" UNKNOWN\n", .{}),
    }

    try buf.flush();
}

fn isKeyDown(key: u8) bool {
    return r.IsKeyDown(KEY_CONFIG_ONE[key]);
}

fn getDownKey() struct { down: bool, key: u8 } {
    // this prefers top keys to bottom, just don't mash i guess
    for (0..0xf) |key| {
        if (isKeyDown(@intCast(key))) {
            return .{ .down = true, .key = @intCast(key) };
        }
    }
    return .{ .down = false, .key = 0 };
}

fn dissasembleChip8Op(codebuffer: [*]u8, pc: usize) !void {
    // Ops given in 4 nib groups (2 u8s) AB CD where A is usually the important one
    // we can get AB with simple index

    const out = std.io.getStdOut();
    var buf = std.io.bufferedWriter(out.writer());
    var w = buf.writer();

    const AB = codebuffer[pc];
    const A = AB >> 4;
    const B = AB & 0xf;
    const CD = codebuffer[pc + 1];
    const C = CD >> 4;
    const D = CD & 0xf;

    try w.print("{x}{x} {x}{x}", .{ A, B, C, D });

    switch (A) {
        0x0 => {
            switch (CD) {
                0xe0 => try w.print("{s:>10}\n", .{"CLS"}),
                0xee => try w.print("{s:>10}\n", .{"RTS"}),
                0x00 => try w.print("{s:>10}\n", .{"NOOP"}),
                else => try w.print(" UNKNOWN 0\n", .{}),
            }
        },
        0x1 => try w.print("{s:>10} ${x:0>2}{x:0>2}\n", .{ "JUMP", B, CD }),
        0x2 => try w.print("{s:>10} ${x:0>2}{x:0>2}\n", .{ "CALL", B, CD }),
        0x3 => try w.print("{s:>10} V{x:0>2}, #${x:0>2}\n", .{ "SKIP.EQ", B, CD }),
        0x4 => try w.print("{s:>10} V{x:0>2}, #${x:0>2}\n", .{ "SKIP.NE", B, CD }),
        0x5 => try w.print("{s:>10} V{x:0>2}, V{x:0>2}\n", .{ "SKIP.EQ", B, C }),
        0x6 => try w.print("{s:>10} V{x:0>2}, #${x:0>2}\n", .{ "MVI", B, CD }),
        0x7 => try w.print("{s:>10} V{x:0>2}, #${x:0>2}\n", .{ "ADI", B, CD }),
        0x8 => {
            switch (D) {
                0x00 => try w.print("{s:>10} V{x:0>2}, V{x:0>2}\n", .{ "MOV", B, C }),
                0x01 => try w.print("{s:>10} V{x:0>2}, V{x:0>2}\n", .{ "OR", B, C }),
                0x02 => try w.print("{s:>10} V{x:0>2}, V{x:0>2}\n", .{ "AND", B, C }),
                0x03 => try w.print("{s:>10} V{x:0>2}, V{x:0>2}\n", .{ "XOR", B, C }),
                0x04 => try w.print("{s:>10} V{x:0>2}, V{x:0>2}\n", .{ "ADD", B, C }),
                0x05 => try w.print("{s:>10} V{x:0>2}, V{x:0>2}\n", .{ "SUB", B, C }),
                0x06 => try w.print("{s:>10} V{x:0>2}, V{x:0>2}\n", .{ "SHR", B, C }),
                0x07 => try w.print("{s:>10} V{x:0>2}, V{x:0>2}\n", .{ "SUBB", B, C }),
                0x0e => try w.print("{s:>10} V{x:0>2}, V{x:0>2}\n", .{ "SHL", B, C }),
                else => try w.print(" UNKNOWN 8\n", .{}),
            }
        },
        0x9 => try w.print("{s:>10} V{x:0>2}, V{x:0>1}\n", .{ "SKIP.NE", B, C }),
        0xa => try w.print("{s:>10} I  , #${x:01}{x:0>2}\n", .{ "MVI", B, CD }),
        0xb => try w.print("{s:>10} ${x:0>1}{x:0>2}(V00)\n", .{ "JUMP", B, CD }),
        0xc => try w.print("{s:>10} V{x:0>2}, #${x:0>2}\n", .{ "RNDMSK", B, CD }),
        0xd => try w.print("{s:>10} V{x:0>2}, V{x:0>2},#${x:0>2}\n", .{ "SPRITE", B, C, D }),
        0xe => {
            switch (CD) {
                0x9e => try w.print("{s:>10} V{x:0>2}\n", .{ "SKIP.KEY", B }),
                0xa1 => try w.print("{s:>10} V{x:0>2}\n", .{ "SKIP.NOKEY", B }),
                else => try w.print(" UNKNOWN e\n", .{}),
            }
        },
        0xf => {
            switch (CD) {
                0x07 => try w.print("{s:>10} V{x:0>2}, DELAY\n", .{ "MOV", B }),
                0x0a => try w.print("{s:>10} V{x:0>2}\n", .{ "WAITKEY", B }),
                0x15 => try w.print("{s:>10} DELAY, V{x:0>2}\n", .{ "MOV", B }),
                0x18 => try w.print("{s:>10} SOUND, V{x:0>2}\n", .{ "MOV", B }),
                0x1e => try w.print("{s:>10} I, V{x:0>2}\n", .{ "ADD", B }),
                0x29 => try w.print("{s:>10} V{x:0>2}\n", .{ "SPRITECHAR", B }),
                0x33 => try w.print("{s:>10} V{x:0>2}\n", .{ "MOVBCD", B }),
                0x55 => try w.print("{s:>10} (I), V0-V{x:0>2}, DELAY\n", .{ "MOVM", B }),
                0x65 => try w.print("{s:>10} V0-V{x:0>2}, (I)\n", .{ "MOVm", B }),
                else => try w.print(" UNKNOWN f\n", .{}),
            }
        },
        else => try w.print(" UNKNOWN\n", .{}),
    }
    try buf.flush();
}
