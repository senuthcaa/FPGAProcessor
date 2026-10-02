transcript on
if {[file exists rtl_work]} {
	vdel -lib rtl_work -all
}
vlib rtl_work
vmap work rtl_work

vlog -vlog01compat -work work +incdir+C:/Users/hoora/Documents/GitHub/FPGAProcessor/FPGAProcessor {C:/Users/hoora/Documents/GitHub/FPGAProcessor/FPGAProcessor/components_tb.v}
vlog -vlog01compat -work work +incdir+C:/Users/hoora/Documents/GitHub/FPGAProcessor/FPGAProcessor {C:/Users/hoora/Documents/GitHub/FPGAProcessor/FPGAProcessor/components.v}

