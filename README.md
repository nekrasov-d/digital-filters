# digital-filters #

RTL (Verilog) digital filter library based on Python scipy library output. Yet.
Maybe I will add filters, based on some other filter design tool outputs later,
or maybe some filters that won't require some offline calculated stuff and work
as is (adaptive filters, for expample).

But currently the workflow is like this:

  0. Chose filter/architecture
  1. Edit parameters in filter_design.py
  2. Run filter_design.py
  3. If it was successfull, then some output files (verilog headers/ memory init
     files) were generated. Put them into project any way you like.
  4. Synthesize design.

The routine might be different for different filters or different architectures,
so I will do more detailed description for each filter in particular.

Designs:

  * FIR
    - RAM FIR (rtl/ram_fir.sv) | sim/hardware verification ok
  * IIR
    - second order sections arch
      - looped SOS IIR (rtl/looped_sos_iir.sv)     | sim/hardware verification ok
      - cascaded SOS IIR (rtl/cascaded_sos_iir.sv) | in progress...
    - monolythic arch
      - in plan...

Goals:

  1. Fun, research
  2. I actually use some of these filters in real hardware.
  3. I would be happy if someone else finds it well done and useful and takes
     it into their academic or commercial design. So please contact me if you
     have any questions

 -- Dmitry Nekrasov <bluebag@yandex.ru>  Wed, 03 Apr 2024 20:56:01 +0300


### filter_design.py ###

All the dessigns here (so far) requires some initializing stuff. This program
is supposed to generate all this stuff. It doesn't have any command line
arguments. To use it you need to edit it. Find "Conrol point" section in the
main loop. Parameter names are self-documented. Select filter type, band, etc.
Which files to generate. Control result with plots.

Supported designs for now:
  * RAM FIR
  * Looped/cascaded sos IIR

### RAM FIR ###

Status:
  * Done
  * Verified in simulation with many different parameters (coverage % is unknown)
  * Verified in hardware

A simple finity impulse response filter that utilizes typical FPGA block RAM
feature: ability to give old value from memory cell in the same clock cycle
while the same cell receives new value. So yep, this design will utilize at
least one RAM block and take LEN clock cycles to produce one output sample,
where LEN is the order of this filter.

It would fit some tasks where high order filter is preferable and data rates are
relatively slow. If it's high and design must process one sample per clock
cycle, well, RAM FIRs could be assembled in a polyphase array anyway, if there
is enough BRAMs.

Spec:
  * Variable data/coefficient (they share the same value) bitwidth
  * Variable tap amount (LEN)
  * Takes LEN clock periods to process one data sample
  * Utilizes two 2^ceil(log2(LEN)) RAM blocks (one for coefficients one for data)
  * Tap coefficients are read-only during runtime
  * You can use filter_design.py program with firwin function to calculate
    coefficints and create $readmemh() initializing file
  * Because the algorithm requires LEN+1 registers, you'd like to create 510-tap
    filter rather than 512 because 512-tap filter is going to utilize 1024-word
    RAM block.

Verification:
  * Common for all filters yet, see specialized section (Testbench)

### SOS IIR ###

IIR kind is populated by some architectures. Some of them (monolythic) are
supposed to be general, but others are likely specified and based on some
observation of what scipy.iirfilter() returns in BUTTERWORTH mode. It MAY work
if you use another tools to generate coefficints or another approximations. And
it would be great as a research point. But for now I suggest to use
filter_design.py program to generate filter coefficients, it makes all checks so
that if it doesn't fail with message, it means that RTL design should work (it
is strictly necessary to run testbench simulation anyway).

So what are these observatons? I used to run scipy.iirfilter() with different
parameters and found out that most of the coefficients actually has fixed
values, or at least fixed range values. Here is the typical output (formatted):

+--------+--------------+--------------+--------------+--------------+--------------+--------------+
|Section |     b0       |      b1      |     b2       |     a0       |      a1      |     a2       |
+--------+--------------+--------------+--------------+--------------+--------------+--------------+
|   0    | 6.619723e-02 | 1.323945e-01 | 6.619723e-02 | 1.000000e+00 | 5.910374e-01 | 9.542512e-02 |
|   1    | 1.000000e+00 | 2.000000e+00 | 1.000000e+00 | 1.000000e+00 | 6.347438e-01 | 1.764302e-01 |
|   2    | 1.000000e+00 | 2.000000e+00 | 1.000000e+00 | 1.000000e+00 | 7.352009e-01 | 3.626168e-01 |
|   3    | 1.000000e+00 | 2.000000e+00 | 1.000000e+00 | 1.000000e+00 | 9.268586e-01 | 7.178339e-01 |
+--------+--------------+--------------+--------------+--------------+--------------+--------------+

  1. b0 and b2 are always 1 for all sections other than 0th
  2. b1 either 2 or -2 for all sections other than 0th (depends on zero_pass parameter)
  3. a0 is always 1
  4. for 0th section, b0, b1, and b2 are in range from 0 to 1
  5. all a2's are in range from 0 to 1
  6. all a1's are in range from 0 to 2 or from -2 to 0 (depends on zero_pass parameter)

So RTL is written with this assumptions and won't work correctly if they are violated.

It was also observed that if cutoff is set in the center of signal spectrum, a1's became 0.
I think synthesizers should optimize logic in this case and we don't need to do
it manually. But if in some case you get area results for cutoff=fs/2 that doesn't
meet expectations, maybe this cirquicy requires manual optimization.

IMPORTANT NOTE! Scipy works with TRANSPOSED architecture. Its functions
generates and receives a1 and a2 vaues that are inverted relative to DIRECT
form. But the RTL design is made with DIRECT form, so if scipy is used to
generate it's coefficients, then a1 and a2 must be inverted. filter_design.py
does this thing, it returns values for DIRECT form, NOT TRANSPOSED.

Particular implementations are:

#### Looped sos IIR ####

Status:
  * Done
  * Verified in simulation with many different parameters (coverage % is unknown)
  * Verified in hardware

This architecture shares same memory among sections. Calculation results inside any section
(z-1 and z-2 registers) are saved inside memory (not supposed to be big because
amount of sections can't be big) and re-used for the next sample.

Pros:
  * a1 and a2 multipliers are shared

Cons:
  * Hangs in a busy state N cycles where N is the amount of sections

Scheme: img/looped_sos_iir.png

Usage: May be used with iir.sv wrapper and "LOOPED_SOS" value for ARCHITECTURE parameter

More details: rtl/looped_sos_iir.sv file annotation

#### Cascaded sos IIR ####

Status:
  * In progress...

The same as looped sos iir, but sections don't share resources. Since this,
filter may work as a pipeline and process 1 sample per clock cycle (with latency
of N though, where N is the amount of sections)

Pros:
  * Performance. 1 sample per 1 clock

Cons:
  * Requires N times more multipliers and adders than looped sos IIR.


Scheme: img/looped_sos_iir.png may be used as a referene. The difference is that
sections are unrolled right instead looping back into z0.

Usage: May be used with iir.sv wrapper and "CASCADED_SOS" value for ARCHITECTURE parameter

More details: rtl/cascased_sos_iir.sv

### Testbench ###

Modelsim oriented routine, supposed to work in command line with GUI only for
intensive debug case.

It could be used as is only if you have Linux distro and Modelsim (vsim bin is
visible through $PATH)

The testbench architecture is like this:
  * Reused Verilog core that applying values and calculate errors
  * Individual python wrapping programs that reuse this core.

Reused core (tb.sv) could be used manually without Python wrappers, if all
required data and parameters were preliminary generated.

Available wrapper programs:
  * iir_test.py

Workflow is similar to filter_design.py. Open file, edit parameters with obvious
meanings, wait for the results.

iir_test.py workflow example:

     | manual parameters set                                                               ^ log
     |                                                                                     |
  +--|----------------------------------------------------------------------------------------+
  |  v              +-------------+                                                        |  |
  |                 |gen test data|--------+------------+                                  |  |
  |   iir_test.py   +-------------+        v            |                                  |  |
  |                                 +------------+      |                                  |  |
  |                   +------------>|gen ref data|----- | ------------------+              |  |
  |                   |             +------------+      |                   |              |  |
  +------+-------------------------------------------------------+----------------------------+
         |            ^                                 |        |vsim -do  |              |
         |            |                                 |        |make.tcl  |              |
         |call        |coeffs                           |        |          |              |
         |            |                                 |   +----------+    |              |
         |            |                                 |   | make.tcl |    |              |
         |            |                                 |   +----------+    |              |
         |            |                                 v        |sim       v              |
         |            |                            +---------+   |     +---------+         |
         |            |                            |input.txt|   |     | ref.txt |         |
         |            |                            +---------+   |     +---------+         |
         v            |                                 |        v          |              |
      +------------------+                      +-------------------------------------+    |
      |                  |    +-----------+     |       |                   v         |    |
      | filter_design.py |--->| coeffs.vh |---->|--+    |  tb.sv         compare -----|----+
      |                  |    +-----------+     |  |    |                   ^         |  score
      +------------------+                      +-------------------------------------+
                                                   |    |                   |
                                                   v    v data_i            | data_o
                                                +-------------------------------------+
                                                |                                     |
                                                |             RTL CODE                |
                                                |                                     |
                                                +-------------------------------------+


### Authors ###

 -- Dmitry Nekrasov <bluebag@yandex.ru>  Wed, 03 Apr 2024 21:33:04 +0300


### LICENSE ###

MIT


