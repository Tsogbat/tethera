# Tethera Terminal - Zsh Integration
# This file provides OSC 133 shell integration for block-based terminal

# OSC 133 escape sequences for semantic shell integration
# A = Prompt start, B = Command start, C = Output start, D = Command end

__tethera_prompt_start() {
    printf '\033]133;A\007'
}

__tethera_command_start() {
    printf '\033]133;B\007'
}

__tethera_output_start() {
    printf '\033]133;C\007'
}

__tethera_command_end() {
    local exit_code=$?
    printf '\033]133;D;%d\007' "$exit_code"
    # Send OSC 7 with current working directory for directory tracking
    printf '\033]7;file://%s%s\007' "$(hostname)" "$(pwd)"
    return $exit_code
}

# Hook into zsh's prompt system
if [[ -n "$ZSH_VERSION" ]]; then
    # precmd runs before each prompt
    precmd_functions+=(__tethera_prompt_start)
    
    # preexec runs before each command execution
    __tethera_preexec() {
        __tethera_command_start
        __tethera_output_start
    }
    preexec_functions+=(__tethera_preexec)
    
    # Add command end marker after each command
    # This is called via PROMPT_COMMAND equivalent in zsh
    __tethera_precmd() {
        __tethera_command_end
    }
    # Insert at beginning so it runs before prompt_start
    precmd_functions=(__tethera_precmd "${precmd_functions[@]}")
fi
