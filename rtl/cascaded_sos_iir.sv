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
 * SOON!
 *
 *-- Dmitry Nekrasov <bluebag@yandex.ru> Thu, 21 Mar 2024 21:05:25 +0300
 */

`include "defines.vh"

module cascaded_sos_iir #(
  parameter                         TYPE         = "lowpass",
  parameter                         ORDER        = 16,
  parameter                         DW           = 16, // Data width
  parameter                         CW           = 16, // Coefficints width
  parameter                         OB           = 0,  // Overhead bits. See annotation
  parameter                         CW_AMOUNT    = $ceil(ORDER/2)*2 + 3, // Do not override!
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

assign data_o = 'x;
assign data_valid_o = 1'b0;

endmodule
