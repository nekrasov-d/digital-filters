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
 * This module is a wrapper that holds all available architectures. Because all
 * irr filter architectures here have same interface (at least yet) (except for
 * parameters maybe) it is convinient to use them like this.
 *
 * Valid TYPE parameter values:
 *     "lowpass"
 *     "highpass"
 *
 * bandpass and bandstop filters are supposed to be impemented with sequenced
 * highpass and lowpass instances
 *
 * Valid ARCHITECTURE
 *    "LOOPED_SOS"
 *
 * "MONOLYTHIC" and "CASCAED_SOS" are in plan.
 *
 * For more details read main lib README.md, scpecific architecture module file
 * annotations and maybe some filter_design.py details if I miss something in
 * details/context
 *
 * -- Dmitry Nekrasov <bluebag@yandex.ru>   Sun, 07 Apr 2024 13:47:24 +0300
 */

module iir #(
  parameter                         TYPE                   = "lowpass",   // See moodule description
  parameter                         ARCHITECTURE           = "LOOPED_SOS", // for all valid options
  parameter                         ORDER                  = 16,
  parameter                         DW                     = 16, // Data width
  parameter                         CW                     = 16, // Coefficints width
  parameter                         CW_AMOUNT              = $ceil(ORDER/2)*2 + 3, // Do not override!
  parameter [CW_AMOUNT-1:0][CW-1:0] SOS_ARCH_COEFFS        = '{default:0},
  parameter [ORDER*2-1  :0][CW-1:0] MONOLYTHIC_ARCH_COEFFS = '{default:0}
) (
  input                 clk_i,
  input                 srst_i,
  input                 sample_valid_i,
  input        [DW-1:0] data_i,
  output logic [DW-1:0] data_o,
  output logic          data_valid_o
);

generate
  if( ARCHITECTURE=="MONOLITHIC" )
    begin : monolythic_iir

      // synopsys translate_off
      initial $fatal( "Monolithic IIR architecture wasn't impemented yet" );
      // synopsys translate_on
      assign data_o       = 'z;
      assign data_valid_o = 1'b0;

    end // monolythic_iir
  else if( ARCHITECTURE=="LOOPED SOS" )
    begin : looped_sos_iir

      looped_sos_iir #(
        .TYPE           ( TYPE                        ),
        .ORDER          ( ORDER                       ),
        .DW             ( DW                          ),
        .CW             ( CW                          ),
        .COEFFICIENTS   ( SOS_ARCH_COEFFS             ),
        .RAMSTYLE       ( "logic"                     )
      ) iir_inst (
        .clk_i          ( clk_i                       ),
        .srst_i         ( srst_i                      ),
        .start_i        ( sample_valid_i              ),
        .data_i         ( data_i                      ),
        .data_o         ( data_o                      ),
        .data_valid_o   ( data_valid_o                )
      );

    end // looped_sos_iir
  else if( ARCHITECTURE=="CASCADED SOS" )
    begin : cascaded_sos_iir

//      cascaded_sos_iir #(
//        .TYPE           ( TYPE                        ),
//        .ORDER          ( ORDER                       ),
//        .DW             ( DW                          ),
//        .CW             ( CW                          ),
//        .COEFFICIENTS   ( SOS_ARCH_COEFFS             )
//      ) iir_inst (
//        .clk_i          ( clk_i                       ),
//        .srst_i         ( srst_i                      ),
//        .start_i        ( start_i                     ),
//        .data_i         ( data_i                      ),
//        .data_o         ( data_o                      ),
//        .data_valid_o   ( data_valid_o                )
//      );

    end // cascaded_sos_iir
  else
    begin
      // synopsys translate_off
        initial $fatal( "%m: Unknown IIR architecture %s", ARCHITECTURE );
      // synopsys translate_on
      assign data_o       = 'z;
      assign data_valid_o = 1'b0;
    end
endgenerate

endmodule
