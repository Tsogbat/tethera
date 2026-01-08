# Tethera Terminal - Bash Integration
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
    return $exit_code
}

# Install hooks for bash
if [[ -n "$BASH_VERSION" ]]; then
    # PROMPT_COMMAND runs before each prompt
    __tethera_prompt_command() {
        __tethera_command_end
        __tethera_prompt_start
    }
    
    # Prepend to existing PROMPT_COMMAND
    if [[ -z "$PROMPT_COMMAND" ]]; then
        PROMPT_COMMAND="__tethera_prompt_command"
    else
        PROMPT_COMMAND="__tethera_prompt_command;$PROMPT_COMMAND"
    fi
    
    # DEBUG trap runs before each command (like preexec in zsh)
    __tethera_debug_trap() {
        # Only trigger on actual commands, not PROMPT_COMMAND
        if [[ "$BASH_COMMAND" != "__tethera_prompt_command" ]] && \
           [[ "$BASH_COMMAND" != "__tethera_command_end" ]] && \
           [[ "$BASH_COMMAND" != "__tethera_prompt_start" ]]; then
            __tethera_command_start
            __tethera_output_start
        fi
    }
    trap '__tethera_debug_trap' DEBUG
fi
