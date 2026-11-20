import Foundation

/// Spec 026 FR-005: the script that replaces the app after CamLid has quit. It runs as
/// `sh <script> <process id> <installed app> <staged app> <backup> <launch arguments…>`.
public enum UpdateSwap {
    public static let script = """
    #!/bin/sh
    # Waits for CamLid to quit, moves the installed app to the backup, moves the staged app into its place and opens it
    # with the arguments it was started with. If the move fails, the old app goes back.
    pid="$1"; installed="$2"; staged="$3"; backup="$4"
    shift 4
    while kill -0 "$pid" 2>/dev/null; do sleep 0.2; done
    rm -rf "$backup" && mv "$installed" "$backup" || exit 1
    if mv "$staged" "$installed"; then
        rm -rf "$(dirname "$staged")"
        open -n "$installed" --args "$@"
    else
        mv "$backup" "$installed"
        exit 1
    fi

    """
}
