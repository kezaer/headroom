/// One shell contract for every official-CLI handoff. Keeping the trap and marker
/// writes shared prevents Claude and Codex from drifting on cleanup or relaunch state.
enum SetupCompletionCommand {
    static func wrap(
        _ invocation: String,
        marker: SetupCompletionMarker,
        mode: SetupHandoffMode
    ) -> String {
        let pending = shellQuoted(marker.pendingPath)
        let completed = shellQuoted(marker.completedPath)
        let modeName = mode == .deviceCode ? "deviceCode" : "standard"
        return """
        umask 077
        typeset -gr HEADROOM_SETUP_SCRIPT="$0"
        print -r -- "\(modeName):$$" > \(pending) || exit 73
        function headroom_setup_completed {
          typeset setup_status=$?
          typeset marker_owner=""
          IFS= read -r marker_owner < \(pending) 2>/dev/null || true
          if [[ "$marker_owner" == "\(modeName):$$" ]]; then
            print -r -- "complete:${setup_status}" > \(completed)
            rm -f -- \(pending)
            rm -f -- "$HEADROOM_SETUP_SCRIPT"
          fi
        }
        trap headroom_setup_completed EXIT
        trap 'exit 129' HUP
        trap 'exit 130' INT
        trap 'exit 143' TERM
        \(invocation)
        exit $?
        """
    }

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
