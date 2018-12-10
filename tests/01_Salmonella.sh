#!/bin/bash
set -e
NUMCPUS=2

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
mv taxonomy library $tmpdir/

# Build the database
db=$wd/GTDB_Kraken
for i in $tmpdir/library/gtdb/*.fna; do
  kraken-build --add-to-library $i --db $db
done
mv -v taxonomy $db
kraken-build --build --db $db --threads $NUMCPUS

# TODO test against the database

