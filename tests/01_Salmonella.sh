#!/bin/bash
set -e

wd=$(dirname $0);

tmpdir=$(mktemp --directory ./$wd/gtdb_kraken.XXXXXX)
trap ' { rm -rf $tmpdir; } ' EXIT
echo "Temp dir is $tmpdir"

inputTsv="$tmpdir/Salmonella.tsv";
grep g__Salmonella $wd/../data/gtdb.2018-12-10.tsv > $inputTsv || {
  echo "ERROR: no Salmonella was found in $inputTsv";
  exit 1
}
perl $wd/../scripts/gtdbToTaxonomy.pl --infile $inputTsv

