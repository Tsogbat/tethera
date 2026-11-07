# Tethera — bash integration
# Emits OSC 133 semantic prompt marks and OSC 7 working-directory updates so
# Tethera can split the session into blocks. Loaded through Tethera's --rcfile shim.

[[ $- == *i* ]] || return 0
[[ -n "${__tethera_integrated-}" ]] && return 0
__tethera_integrated=1
__tethera_at_prompt=0
__tethera_command_running=0
__tethera_status=0

__tethera_osc() {
    builtin printf '\e]%s\a' "$1"
}

__tethera_save_status() {
    __tethera_status=$?
}

__tethera_prompt_command() {
    if [[ $__tethera_command_running == 1 ]]; then
        __tethera_osc "133;D;${__tethera_status}"
        __tethera_command_running=0
    fi
    __tethera_osc "7;file://${HOSTNAME}${PWD}"
    __tethera_osc "133;A"
    __tethera_at_prompt=1
    return $__tethera_status
}

__tethera_debug_trap() {
    [[ $__tethera_at_prompt == 1 ]] || return 0
    [[ -n "${COMP_LINE-}" ]] && return 0
    case "$BASH_COMMAND" in
        __tethera_save_status*|__tethera_prompt_command*) return 0 ;;
    esac
    __tethera_at_prompt=0
    __tethera_command_running=1
    __tethera_osc "133;B"
    __tethera_osc "133;C"
}

trap '__tethera_debug_trap' DEBUG
PROMPT_COMMAND="__tethera_save_status${PROMPT_COMMAND:+;$PROMPT_COMMAND};__tethera_prompt_command"
