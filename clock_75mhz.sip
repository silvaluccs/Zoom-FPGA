set_global_assignment -entity "clock_75mhz" -library "lib_clock_75mhz" -name IP_TOOL_NAME "altera_pll"
set_global_assignment -entity "clock_75mhz" -library "lib_clock_75mhz" -name IP_TOOL_VERSION "23.1"
set_global_assignment -entity "clock_75mhz" -library "lib_clock_75mhz" -name IP_TOOL_ENV "mwpim"
set_global_assignment -library "lib_clock_75mhz" -name SPD_FILE [file join $::quartus(sip_path) "clock_75mhz.spd"]

set_global_assignment -library "lib_clock_75mhz" -name MISC_FILE [file join $::quartus(sip_path) "clock_75mhz_sim/clock_75mhz.vo"]
