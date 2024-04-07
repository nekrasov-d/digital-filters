/*
 * MIT License
 *
 * Copyright (c) 2024 Dmitriy Nekrasov
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 *
 * ---------------------------------------------------------------------------------
 *
 * FIR filter impementation utilizing block RAM. Well, it could also use
 * registers if you want (this is controlled by RAMSTYLE parameter), but it is
 * expected that there is a lot of taps desired if we impement FIR, so
 * register-based design will consume too much of them.
 *
 * As you may see by default RAMSTYLE parameter value, I work with Intel FPGA's
 * and if you use different vendor you may need to edit ram.sv and add a block
 * with "ramstyle" attribute which explicitly tells synthesizer to use exactly
 * this type of block memory. Or just set RAMSTYLE = "default" and hope that
 * synthesizer get it right (big chance it will).
 *
 * For more details, read main README.md. You can use filter_design.py program
 * to generate memory initializing file for this module.
 *
 * -- Dmitry Nekrasov <bluebag@yandex.ru>   Sun, 07 Apr 2024 14:06:02 +0300
 *
 */

`include "defines.vh"

module ram_fir #(
  parameter DW      = 16,
  parameter LEN         = 511,
  parameter COEFFS_FILE = "none.mem",
  parameter RAMSTYLE    = "M9K"
) (
  input                 clk_i,
  input                 srst_i,
  input                 sample_valid_i, // Strobe
  input        [DW-1:0] data_i,         // Doesn't required to remain stable without sample_valid_i
  output logic [DW-1:0] data_o,         // Always stable and refreshed with same frequency as sample_valid_i comes
  output logic          data_valid_o    // Formal stuff for testbench, you may sample data_o
);                                      // on any cycle you want (with same clock of course)

localparam RAM_AWIDTH = $clog2(LEN);

//**************************************************************************
// Control plane

logic [RAM_AWIDTH-1:0] cnt;

enum logic [1:0] {
  INIT_S,
  WAIT_START_S,
  RUN_S,
  LAST_OP_S
} state;

always_ff @( posedge clk_i )
  if( srst_i )
    state <= INIT_S;
  else
    case( state )
      INIT_S       : state <= WAIT_START_S;
      WAIT_START_S : state <= sample_valid_i ? RUN_S : WAIT_START_S;
      RUN_S        : state <= ( cnt == LEN ) ? LAST_OP_S : RUN_S;
      LAST_OP_S    : state <= WAIT_START_S;
    endcase

always_ff @( posedge clk_i )
  case( state )
    WAIT_START_S : cnt <= sample_valid_i ? 1 : 0;
    RUN_S        : cnt <= cnt + 1;
    default      : cnt <= 0;
  endcase

//*****************************************************************************
// Data plane

//input data storage
logic [DW-1:0]         data_reg;
// ram/rom wires
logic [RAM_AWIDTH-1:0] rdaddr;
logic [RAM_AWIDTH-1:0] wraddr;
logic [DW-1:0]         wrdata;
logic [DW-1:0]         value;
logic [DW-1:0]         coeff;
logic                  wren;

logic signed [DW*2-1:0] mult;
logic [DW-1:0]          mult_bitshift;
logic [DW-1:0]          accum;

always_ff @( posedge clk_i )
  if( sample_valid_i )
    data_reg <= data_i;

always_comb
  case( state )
    RUN_S   : rdaddr = LEN - 1 - cnt;
    default : rdaddr = LEN - 1;
  endcase

always_comb
  case( state )
    LAST_OP_S : wraddr = 0;
    default   : wraddr = rdaddr + 2;
  endcase

always_comb
  case( state )
    LAST_OP_S : wrdata = data_reg;
    default   : wrdata = value;
  endcase

assign wren   = state==RUN_S || state==LAST_OP_S;

ram #(
  .DWIDTH       ( DW            ),
  .AWIDTH       ( RAM_AWIDTH    ),
  .RAMSTYLE     ( RAMSTYLE      )
) values (
  .clk          ( clk_i         ),
  .wraddr       ( wraddr        ),
  .rdaddr       ( rdaddr        ),
  .wren         ( wren          ),
  .d            ( wrdata        ),
  .q            ( value         )
);

rom #(
  .DWIDTH       ( DW            ),
  .AWIDTH       ( RAM_AWIDTH    ),
  .INIT_FILE    ( COEFFS_FILE   )
) coefficients (
  .clk_i        ( clk_i         ),
  .rdaddr_i     ( rdaddr        ),
  .rddata_o     ( coeff         )
);

assign mult          = `s(value) * `s(coeff);
assign mult_bitshift = mult >> DW;

always_ff @( posedge clk_i )
  accum <= state==RUN_S ? accum + mult_bitshift : '0;

always_ff @( posedge clk_i )
  if( srst_i )
    data_o <= '0;
  else
    if( state==LAST_OP_S )
      data_o <= accum;

endmodule






