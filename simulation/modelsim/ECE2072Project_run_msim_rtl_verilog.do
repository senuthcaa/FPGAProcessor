transcript on
if {[file exists rtl_work]} {
	vdel -lib rtl_work -all
}
vlib rtl_work
vmap work rtl_work

vlog -vlog01compat -work work +incdir+C:/Users/hoora/Documents/GitHub/FPGAProcessor/FPGAProcessor {C:/Users/hoora/Documents/GitHub/FPGAProcessor/FPGAProcessor/proc_extension_tb.v}
vlog -vlog01compat -work work +incdir+C:/Users/hoora/Documents/GitHub/FPGAProcessor/FPGAProcessor {C:/Users/hoora/Documents/GitHub/FPGAProcessor/FPGAProcessor/proc_extension.v}
vlog -vlog01compat -work work +incdir+C:/Users/hoora/Documents/GitHub/FPGAProcessor/FPGAProcessor {C:/Users/hoora/Documents/GitHub/FPGAProcessor/FPGAProcessor/components.v}
vlog -vlog01compat -work work +incdir+C:/Users/hoora/Documents/GitHub/FPGAProcessor/FPGAProcessor {C:/Users/hoora/Documents/GitHub/FPGAProcessor/FPGAProcessor/BCD_decoder.v}

