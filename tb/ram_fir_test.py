#!bin/pythion3
#
# MIT License
#
# Copyright (c) 2024 Dmitriy Nekrasov
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
# ---------------------------------------------------------------------------------
#
# Verilog testbench tb.sv wrapping program written to automatize sos IIR filter
# designs. See main README.md for details, there is a nice block scheme exactly
# for this case.
#
# Needs a Linux distro and modelsim. vsim binary must be visible through $PATH
#
# This is rather an example, it is expected that it would be automatically
# paremeterized to automatically run in loop through a set of parameters, or
# tuned for a individual case if a filter instance is supposed to be configured
# once per project and never changed later.
#
# Run:
#   python3 iir_test.py
#
# -- Dmitry Nekrasov <bluebag@yandex.ru> Thu, 21 Mar 2024 21:05:25 +0300
#

import numpy as np
import scipy.signal as signal
#from scipy.signal import sosfilt
import sys
import os
import subprocess
cwd = os.getcwd()
sys.path.append( cwd + '/../')
from filter_design import gen_ram_fir

############################################################################
# Test parameters

DATA_WIDTH               = 24
COEFFICIENT_WIDTH        = 24
NTAPS                    = 511
FSAMPLE                  = 44100
CUTOFF                   = 200
FILTER_TYPE              = ( "lowpass", "highpass" )[1]
RAM_FIR_INIT_FILE_NAME   = "test.mem"
CLK_PER_SAMPLE           = NTAPS + 10
SHOW_PSD                 = False
TESTBENCH_MODE           = ( "manual", "automatic" )[1]

############################################################################
# Get filter coefficients

b = gen_ram_fir( ntaps            = NTAPS,
                 cutoff           = CUTOFF,
                 cw               = COEFFICIENT_WIDTH,
                 filter_type      = FILTER_TYPE,
                 rom_fname        = RAM_FIR_INIT_FILE_NAME
                 )

############################################################################
# Translate config to verilog

f = open( "testbench_parameters.v", "w" )
f.write(f"`define RAM_FIR\n")
f.write(f"parameter DATA_WIDTH             = {DATA_WIDTH};\n")
f.write(f"parameter COEFFICIENT_WIDTH      = {COEFFICIENT_WIDTH};\n")
f.write(f"parameter ORDER                  = {NTAPS};\n")
f.write(f'parameter RAM_FIR_INIT_FILE_NAME = "{RAM_FIR_INIT_FILE_NAME}";\n')
f.write(f'parameter CLK_PER_SAMPLE         = {CLK_PER_SAMPLE};\n')
f.write(f'parameter TEST_DATA_FNAME        = "input.txt";\n')
f.write(f'parameter REF_DATA_FNAME         = "ref.txt";\n')
f.write(f'parameter TESTBENCH_MODE         = "{TESTBENCH_MODE}";\n')
f.close()


############################################################################
# Prepare test data

N =  1000
dw = DATA_WIDTH
cw = COEFFICIENT_WIDTH

max_val =  2**(dw-1)-1
min_val = -2**(dw-1)

test_data = np.random.randint( min_val//4, max_val//4, N )

#ref_data = signal.convolve( test_data, b )[:len(test_data)]
ref_data = signal.lfilter( b, [1.0], test_data )

# because in ram_fir.sv design input data has one additional delay for
# bufferization
ref_data = np.append( 0., ref_data[:-1] )

ref_data_floored = np.zeros_like( ref_data, dtype=int )
for i in range(len(ref_data)):
    ref_data_floored[i] = int( round( ref_data[i] * 2**(cw-1) ) / 2**(cw-1) )
    if( ref_data_floored[i] > max_val ):
        ref_data_floored[i] = max_val
    if( ref_data_floored[i] < min_val ):
        ref_data_floored[i] = min_val


if( SHOW_PSD ):
    import matplotlib.pyplot as plt
    fig, (ax0, ax1 ) = plt.subplots(2,1, layout='constrained')
    ax0.psd( test_data )
    ax1.psd( ref_data_floored )
    plt.show()
    exit()


td = open( "input.txt", "w" )
rd = open( "ref.txt",   "w" )
for i in range(N):
    td.write("%d\n" % test_data[i])
    rd.write("%d\n" % ref_data_floored[i])
td.close()
rd.close()


if( TESTBENCH_MODE == "automatic" ):
    run_vsim = "vsim -c -do make.tcl"
    vsim = subprocess.Popen( run_vsim.split(), stdout=subprocess.PIPE )
    res = vsim.communicate()
    print(res)
    try:
        f = open( "score.txt", "r" )
        score = f.readlines()[0][1:-2]
        f.close()
    except FileNotFoundError:
        score = "No score.txt were generated by make.tcl routine"
    f = open( "log", "a" )
    f.write("-------------------------- ram fir test ----------------------------\n")
    f.write( f"Paramters: DW/CW {DATA_WIDTH}/{COEFFICIENT_WIDTH} {FILTER_TYPE} ")
    f.write( f"ntaps: {NTAPS} Fsample : {FSAMPLE} cutoff: {CUTOFF}\n")
    f.write( f"Results: {score}\n")
    f.close()
    # clean
    try:
        os.remove("test.mem")
        os.remove("testbench_parameters.v")
        os.remove("input.txt")
        os.remove("ref.txt")
        os.remove("score.txt")
        os.remove("transcript")
        os.remove("vsim.wlf")
        import shutil
        shutil.rmtree( "work", ignore_errors=True )
    except FileNotFoundError:
        pass






