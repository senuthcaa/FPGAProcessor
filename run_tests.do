# run_tests.do
# Demonstrates the testbenches. Each one is run twice: on the working design, where it should pass,
#     and on the deliberately broken copy, where it should catch the bugs. A summary is printed at the end.
#
# In ModelSim:       cd to the folder that holds this file (the project folder), then type
#                        do run_tests.do
# From a terminal:   vsim -c -do "do run_tests.do; quit -f"
#
# Every test is compiled into a fresh library called rt_work, because the broken files use the same
#     module names as the working ones.

transcript off
onbreak {resume}
onerror {resume}
#do not open the testbench source window every time a testbench reaches its $stop
quietly set PrefSource(OpenOnBreak) 0

#test number, testbench, design shown in the summary, files to compile, expected result
quietly set rt_tests {
	{1 components_tb     components.v            {components.v components_tb.v}                                  pass}
	{2 components_tb     broken_components.v     {broken_components.v components_tb.v}                           fail}
	{3 proc_extension_tb proc_extension.v        {components.v proc_extension.v proc_extension_tb.v}             pass}
	{4 proc_extension_tb broken_proc_extension.v {components.v broken_proc_extension.v proc_extension_tb.v}      fail}
}

#components_tb counts the failures of each component in these integers
quietly set rt_components {
	{"sign extender" se_errors}
	{"tick FSM" tick_errors}
	{"mux" mux_errors}
	{"alu" alu_errors}
	{"register_n" reg_errors}
}

proc rt_rule {ch} {
	echo [string repeat $ch 86]
}

proc rt_banner {text} {
	echo ""
	rt_rule =
	echo " $text"
	rt_rule =
}

#the project folder is the one with ECE2072Project.qpf and the broken files in it
#simulation/modelsim also has copies of some files (including an old proc_extension_tb.v), so it must not be used
proc rt_is_project {dir} {
	return [expr {[file exists [file join $dir ECE2072Project.qpf]] && [file exists [file join $dir broken_components.v]]}]
}

#use the current folder if it is the project folder, else two folders up (where ModelSim starts when Quartus opens it),
#    else the folder of the "do <path>/run_tests.do" command that started this script
proc rt_find_project {} {
	if {[rt_is_project .]} { return 1 }
	set dirs [list [file join .. ..]]
	for {set i [info frame]} {$i >= 1} {incr i -1} {
		if {[catch {info frame $i} f] || ![dict exists $f cmd]} { continue }
		if {[regexp {(?:^|[;\s])do\s+"?([^\s;"]*run_tests\.do)} [dict get $f cmd] -> path]} {
			lappend dirs [file dirname $path]
		}
	}
	foreach dir $dirs {
		if {[rt_is_project $dir]} {
			cd [file normalize $dir]
			echo "run_tests.do: running in [pwd]"
			return 1
		}
	}
	return 0
}

#compile the files into a fresh rt_work library, returns 0 if any file fails to compile
proc rt_compile {files} {
	catch {quit -sim}
	if {[file exists rt_work]} {
		if {[catch {vdel -lib rt_work -all}]} { catch {file delete -force rt_work} }
	}
	if {[catch {vlib rt_work}]} {
		echo "** could not create the rt_work library"
		return 0
	}
	foreach f $files {
		if {[catch {vlog -quiet -nologo -vlog01compat -work rt_work $f}]} {
			echo "** $f did not compile"
			return 0
		}
	}
	return 1
}

#read an integer from the paused simulation, returns -1 if it cannot be read
proc rt_int {path} {
	if {[catch {examine -radix decimal $path} v]} { return -1 }
	set v [string trim $v]
	if {[regexp {^-?[0-9]+$} $v]} { return $v }
	return -1
}

#run one test, returns {failures detail}, with failures = -1 if the test could not run
proc rt_run {num tb design files expect} {
	global rt_components
	if {$expect eq "pass"} { set want "should PASS" } else { set want "should FAIL, showing the testbench catches the bugs" }
	rt_banner "TEST $num: $tb on $design ($want)"

	if {![rt_compile $files]} { return [list -1 "compile error"] }
	if {[catch {vsim -quiet -voptargs=+acc rt_work.$tb}]} { return [list -1 "could not load $tb"] }
	if {[catch {run -all}]} {
		catch {quit -sim}
		return [list -1 "the simulation did not run"]
	}

	if {$tb eq "components_tb"} {
		set fails 0
		set parts {}
		foreach c $rt_components {
			set n [rt_int /components_tb/[lindex $c 1]]
			if {$n < 0} { set fails -1; break }
			incr fails $n
			if {$n > 0} { lappend parts "[lindex $c 0] $n" }
		}
		if {$fails < 0} {
			set detail "results could not be read"
		} elseif {$fails == 0} {
			set detail "0 failures in any component"
		} else {
			set detail "$fails failures: [join $parts {, }]"
		}
	} else {
		set checks [rt_int /$tb/total_checks]
		set fails [rt_int /$tb/total_fails]
		set nsec [rt_int /$tb/n_sections]
		set bad {}
		for {set i 0} {$i < $nsec} {incr i} {
			if {[rt_int "/$tb/res_fails\[$i\]"] > 0} { lappend bad [expr {$i + 1}] }
		}
		if {$fails < 0 || $checks < 0} {
			set fails -1
			set detail "results could not be read"
		} elseif {$fails == 0} {
			set detail "all $checks checks passed"
		} else {
			if {[llength $bad] == 1} {
				set detail "$fails of $checks checks failed, all in section [lindex $bad 0]"
			} else {
				set detail "$fails of $checks checks failed, in sections [join $bad {, }]"
			}
			if {[lindex $bad end] == $nsec} { append detail " (section $nsec is mul, ssi and disp)" }
		}
	}
	catch {quit -sim}
	return [list $fails $detail]
}

proc rt_main {} {
	global rt_tests
	catch {quit -sim}
	if {![rt_find_project]} {
		echo "run_tests.do: cd to the project folder (the one with ECE2072Project.qpf) and run it again"
		return
	}

	set results {}
	foreach t $rt_tests {
		lassign $t num tb design files expect
		lassign [rt_run $num $tb $design $files $expect] fails detail
		lappend results [list $num $tb $design $expect $fails $detail]
	}
	catch {quit -sim}
	if {[file exists rt_work]} {
		if {[catch {vdel -lib rt_work -all}]} { catch {file delete -force rt_work} }
	}

	rt_banner "SUMMARY"
	echo [format " %-5s %-18s %-24s %-9s %-7s %s" "Test" "Testbench" "Design" "Expected" "Result" "Details"]
	rt_rule -
	array set works {}
	foreach r $results {
		lassign $r num tb design expect fails detail
		if {$fails < 0} {
			set result "ERROR"
		} elseif {$fails == 0} {
			set result "PASS"
		} else {
			set result "FAIL"
		}
		set ok [expr {($expect eq "pass" && $result eq "PASS") || ($expect eq "fail" && $result eq "FAIL")}]
		if {![info exists works($tb)]} { set works($tb) 1 }
		if {!$ok} { set works($tb) 0 }
		echo [format " %-5s %-18s %-24s %-9s %-7s %s" $num $tb $design [string toupper $expect] $result $detail]
	}
	rt_rule -
	foreach tb {components_tb proc_extension_tb} {
		if {$works($tb)} {
			echo [format " %-18s WORKS: passes the working design and catches the bugs in the broken one" $tb]
		} else {
			echo [format " %-18s DID NOT behave as expected, see the tests above" $tb]
		}
	}
	rt_rule =
}

quietly rt_main
