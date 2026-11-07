# Tethera — zsh integration
# Emits OSC 133 semantic prompt marks and OSC 7 working-directory updates so
# Tethera can split the session into blocks. Loaded by Tethera's ZDOTDIR shim.

[[ -o interactive ]] || return 0
[[ -n "${__tethera_integrated-}" ]] && return 0
typeset -g __tethera_integrated=1
typeset -gi __tethera_command_running=0

# Blocks are separate, so zsh's "missing newline" marker (an inverse %) would only leak into output.
unsetopt PROMPT_SP 2>/dev/null

__tethera_osc() {
    builtin printf '\e]%s\a' "$1"
}

__tethera_precmd() {
    local status_code=$?
    if (( __tethera_command_running )); then
        __tethera_osc "133;D;${status_code}"
        __tethera_command_running=0
    fi
    __tethera_osc "7;file://${HOST}${PWD}"
    __tethera_osc "133;A"
    return $status_code
}

__tethera_preexec() {
    __tethera_command_running=1
    __tethera_osc "133;B"
    __tethera_osc "133;C"
}

# Run first so $? still holds the command's exit status.
precmd_functions=(__tethera_precmd ${precmd_functions:#__tethera_precmd})
preexec_functions=(${preexec_functions:#__tethera_preexec} __tethera_preexec)
