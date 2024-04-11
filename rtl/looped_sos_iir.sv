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
 * IIR filter with looped second order sections architecture. It means that all
 * the sections share same adder/multipliers and work one after another. It will
 * require more clock cycles to process one sample than pipelined architecture
 * (with same latency though), but may save a lot of gates/dsp blocks by
 * sharing.
 *
 * The design is completely based on what Python's scipy.signal.iirfilter
 * outputs. I mean I just tried to obtain different frequency responses, saw
 * what kind of values it gives and designed filter based on this information.
 * Maybe if I tried more options, these values go outside expected ranges,
 * and this filter would require some modifications. Anyway, coefficient
 * generating program has checks if they are inside ranges and if they aren't it
 * will tell you. See main readme (../README.md) for more details
 *
 * COEFFICIENTS:
 *
 * Let's suppose ORDER = 20 ( implies 10 second order sections ), CW=16
 * COEFFICIENTS parameter port should receive an array like this:
 *
 *      A2[9]         A2[0]     A1[9]           A1[0]      B2        B1        B0
 * { 16'hdead, ..., 16'dbeef, 16'h1234,  ...,  16'habcd, 16'h1111, 16'haaaa, 16'habab }
 *
 *
 * Values here are random, of course. All these values are signed fixed point values
 * with all bits being the fractional part. So the actual range of these values are
 * from -1 to 0.99... (depends on bit width). Why feedforward (B*) coefficients has
 * only one value? Read main readme (../README.md).
 *
 * Overflow protection: Despite coefficients are verified to create stable
 * filter (even after rounding) it is still expected that at some "bad" sequence
 * of values it may overflow on some branch. But if we give it some extra bits,
 * then this accumulated big value may be mitigated by ativity of negative gain
 * terms or negative followed samples. OB (Overhead bits) is picked
 * experimentally, but I hope I'll have time to come up with strict math
 * justification later..
 *
 *
 * Wrapper instance example:
 *   iir #(
 *     .TYPE         ( "lowpass"                                      ),
 *     .ARCHITECTURE ( "LOOPED SOS"                                   ),
 *     .ORDER        ( 16                                             ),
 *     .DW           ( DW                                             ),
 *     .CW           ( CW                                             ),
 *     .COEFFICIENTS ( `include "sos_iir_coeffs_lp_24b_8_sections.sv" )
 *   ) iir_filter_instance (
 *     .clk_i ( clk ),
 *    ....
 *
 *-- Dmitry Nekrasov <bluebag@yandex.ru> Thu, 21 Mar 2024 21:05:25 +0300
 */

`include "defines.vh"

module looped_sos_iir #(
  parameter                         TYPE         = "lowpass",
  parameter                         ORDER        = 16,
  parameter                         DW           = 16, // Data width
  parameter                         CW           = 16, // Coefficints width
  parameter                         OB           = 2,  // Overhead bits. See annotation
  parameter                         CW_AMOUNT    = (ORDER/2)*2 + 3, // Do not override!
  parameter [CW_AMOUNT-1:0][CW-1:0] COEFFICIENTS = '{default:0},
  parameter                         RAMSTYLE     = "logic"
) (
  input                        clk_i,
  input                        srst_i,
  input                        start_i, // New sample arrived, launch calculation
  input  signed       [DW-1:0] data_i,
  output logic signed [DW-1:0] data_o,
  output logic                 data_valid_o
);

// Little nested module to reduce bitwidth without overflow
// XXX: nested module declaration is not supported in quartus
//`include "sat.sv"
// How many second order sections do we have
localparam NSECTIONS = ORDER / 2;
localparam CNT_W = $clog2( NSECTIONS );

//*********************************************************************************
// Unpack coefficients

// Uppercase because they are static
logic signed [CW-1:0] B0;
logic signed [CW-1:0] B1;
logic signed [CW-1:0] B2;
logic signed [CW-1:0] A1 [NSECTIONS-1:0];
logic signed [CW-1:0] A2 [NSECTIONS-1:0];

assign B0 = COEFFICIENTS[0];
assign B1 = COEFFICIENTS[1];
assign B2 = COEFFICIENTS[2];

always_comb
  for( int i = 0; i < NSECTIONS; i++ )
    begin : unpack_coeffs
      A1[i] = COEFFICIENTS[i+3];
      A2[i] = COEFFICIENTS[i+3+NSECTIONS];
    end // unpack_coeffs

//*********************************************************************************
// Actual wires / registers

// control logic
logic        [CNT_W-1:0]    cnt, cnt_d;
logic                       wren;
logic                       start_d;
logic                       last_section;
logic                       last_section_d;
// filter memory
logic signed [DW+CW+OB-1:0] z0;
logic signed [DW+OB-1:0]    z1, z2;
// feedforward path
logic signed [DW+CW+OB:0]   b0_mult;
logic signed [DW+CW+OB+1:0] b1_mult;
logic signed [DW+CW+OB:0]   b2_mult;
logic signed [DW+CW+OB+2:0] ffs; // feedforward sum
logic signed [DW+CW+OB-1:0] one_section_loop;
logic signed [DW+CW-2:0]    osl_sat;
// feedback path
logic signed [DW+CW+OB  :0] a1_mult;
logic signed [DW+CW+OB-1:0] a2_mult;
logic signed [DW+CW+OB+1:0] feedback_sum;
logic signed [DW+2+OB:0]    fbs;
logic signed [DW-1+OB:0]    fbs_sat;

//*********************************************************************************
// Control logic

always_ff @( posedge clk_i )
  if( srst_i )
    cnt <= 0;
  else
    if( last_section )
      cnt <= '0;
    else
      if( start_i || ( wren && !last_section_d) )
        cnt <= cnt + 1'b1;

assign last_section = ( cnt == (NSECTIONS-1) );
assign wren         = ( cnt_d > 0 ) || start_d; // enable writing into z* registers

// Delays
always_ff @( posedge clk_i )
  begin
    start_d        <= start_i;
    cnt_d          <= cnt;
    last_section_d <= last_section;
  end

//*********************************************************************************
// filter  memory

always_ff @( posedge clk_i )
  if( start_i )
    z0 <= `s({ data_i, {(CW-1){1'b0}} });
  else
    if( wren )
      z0 <= one_section_loop;

// Another nested module declaration XXX: not supported in quartus
//`include "ram.sv"

// Most likely we won't need real RAM here, it's just registers
// RAMSTYLE == "logic" forces synthesizer to use registers
filters_ram #(
  .DWIDTH   ( DW+OB      ),
  .NWORDS   ( NSECTIONS ),
  .RAMSTYLE ( "logic"   )
) mem_z1 (
  .clk      ( clk_i     ),
  .wraddr   ( cnt_d     ),
  .rdaddr   ( cnt       ),
  .wren     ( wren      ),
  .d        ( fbs_sat   ),
  .q        ( z1        )
);

filters_ram #(
  .DWIDTH   ( DW+OB    ),
  .NWORDS   ( NSECTIONS ),
  .RAMSTYLE ( "logic"   )
) mem_z2 (
  .clk      ( clk_i     ),
  .wraddr   ( cnt_d     ),
  .rdaddr   ( cnt       ),
  .wren     ( wren      ),
  .d        ( z1        ),
  .q        ( z2        )
);

//*********************************************************************************
// Feedforward path

logic signed [CW:0]   b0;
logic signed [CW+1:0] b1;
logic signed [CW:0]   b2;

`define one       `s( { 2'b01, `zeros(CW-1) } )
`define two       `s( { 2'b01, `zeros(CW)   } )
`define minus_two `s( { 2'b11, `zeros(CW)   } )

assign b0 = ( cnt_d == 0 ) ? B0 : `one;
assign b1 = ( cnt_d == 0 ) ? B1 : ( TYPE=="highpass" ? `minus_two : `two );
assign b2 = ( cnt_d == 0 ) ? B2 : `one;

assign b0_mult = fbs_sat * b0;
assign b1_mult = z1      * b1;
assign b2_mult = z2      * b2;

assign ffs = b0_mult + b1_mult + b2_mult;

filters_sat #( .IW( $bits(ffs) ), .OW( $bits(one_section_loop) ) ) feedforward_sat ( ffs, one_section_loop );

//*********************************************************************************
// Feedback path

assign a1_mult = z1 * A1[cnt_d] * 2;
assign a2_mult = z2 * A2[cnt_d];
assign feedback_sum = z0 + a1_mult + a2_mult;

assign fbs = ( feedback_sum >> (CW-1) ) + `u(feedback_sum[CW-2]);

filters_sat #( .IW( $bits(fbs) ), .OW( DW+OB ) ) feedback_sat ( fbs, fbs_sat );

//*********************************************************************************
// Output

filters_sat #( .IW( $bits(one_section_loop) ), .OW( $bits(osl_sat) ) ) output_sat (one_section_loop, osl_sat);

always_ff @( posedge clk_i )
  if( last_section_d )
    data_o <= osl_sat >> (CW-1);

always_ff @( posedge clk_i )
  data_valid_o <= last_section_d;

endmodule
