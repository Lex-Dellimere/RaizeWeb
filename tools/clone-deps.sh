#!/usr/bin/env bash
# Clone the libraries raize depends on from outside the framework into the directory that
# contains this raize_web checkout (or the directory given as $1). The framework's own
# packages are submodules under libs/ (`git clone --recursive`). Existing folders are kept.
set -eu
dest=${1:-"$(cd "$(dirname "$0")/../.." && pwd)"}
cd "$dest"
clone() { if [ -d "$2" ]; then echo "have  $2"; else git clone "$1" "$2"; fi; }
clone https://github.com/Lex-Dellimere/Cryptex.git cryptex
clone https://github.com/Lex-Dellimere/Codec.git codec
clone https://github.com/Lex-Dellimere/Press.git press
clone https://github.com/Lex-Dellimere/mbuild.git mbuild
clone https://github.com/The-Mettle-Project/Mettle.git Mettle
