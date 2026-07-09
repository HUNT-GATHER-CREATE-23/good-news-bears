#!/bin/bash
# Good News Bears — refresh the site with the latest stories.
# Double-click in Finder, or run  ./refresh.sh  in Terminal.
cd "$(dirname "$0")" || exit 1
/usr/bin/perl generate.pl && echo "Done. Open index.html in your browser."
