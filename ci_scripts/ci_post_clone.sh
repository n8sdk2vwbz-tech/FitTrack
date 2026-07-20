#!/bin/sh
set -e

# Xcode Cloud klont das Repo aus Git, wo FitTrack/Services/StravaConfig.swift
# bewusst NICHT enthalten ist (siehe .gitignore - das Client Secret soll nie
# im Git-Verlauf landen). Die schon eingecheckte project.pbxproj verweist
# trotzdem fest auf diesen Pfad, der Build würde also ohne diese Datei mit
# "Build input file cannot be found" fehlschlagen. Dieses Skript erzeugt sie
# hier aus Xcode-Cloud-Umgebungsvariablen (App Store Connect > Xcode Cloud >
# Workflow > Umgebung > STRAVA_CLIENT_ID/STRAVA_CLIENT_SECRET als "Secret"
# hinterlegen) - lokal bleibt stattdessen die manuell angelegte, ebenfalls
# nicht eingecheckte Datei mit denselben Werten unangetastet, da dieses
# Skript nur von Xcode Cloud selbst ausgeführt wird.

# CI_WORKSPACE ist in der ci_post_clone-Phase teils noch nicht gesetzt -
# CI_PRIMARY_REPOSITORY_PATH ist die dafür vorgesehene, zu diesem frühen
# Zeitpunkt zuverlässig verfügbare Variable für den Repo-Wurzelpfad.
REPO_ROOT="${CI_PRIMARY_REPOSITORY_PATH:-$CI_WORKSPACE}"
if [ -z "$REPO_ROOT" ]; then
    echo "error: weder CI_PRIMARY_REPOSITORY_PATH noch CI_WORKSPACE ist gesetzt" >&2
    exit 1
fi

CONFIG_DIR="$REPO_ROOT/FitTrack/Services"
CONFIG_PATH="$CONFIG_DIR/StravaConfig.swift"
mkdir -p "$CONFIG_DIR"

CLIENT_ID="${STRAVA_CLIENT_ID:-DEINE_CLIENT_ID}"
CLIENT_SECRET="${STRAVA_CLIENT_SECRET:-DEIN_CLIENT_SECRET}"

echo "Erzeuge $CONFIG_PATH"

cat > "$CONFIG_PATH" <<EOF
import Foundation

/// Automatisch von ci_scripts/ci_post_clone.sh aus den Xcode-Cloud-
/// Umgebungsvariablen STRAVA_CLIENT_ID/STRAVA_CLIENT_SECRET erzeugt - nicht
/// manuell bearbeiten, Änderungen werden beim nächsten Build überschrieben.
enum StravaConfig {
    static let clientId = "$CLIENT_ID"
    static let clientSecret = "$CLIENT_SECRET"
    static let redirectURL = URL(string: "readylift://readylift")!
}
EOF

echo "StravaConfig.swift für Xcode Cloud erzeugt."
