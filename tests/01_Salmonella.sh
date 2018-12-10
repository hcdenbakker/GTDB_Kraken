#!/bin/bash
set -e
NUMCPUS=2

wd=$(dirname $0);

tmpdir=$(mktemp --directory ./$wd/gtdb_kraken.XXXXXX)
trap ' { rm -rf $tmpdir; } ' EXIT
echo "Temp dir is $tmpdir"

# Reduce the input spreadsheet to simply the Salmonella genomes
inputTsv="$tmpdir/Salmonella.tsv";
grep g__Salmonella $wd/../data/gtdb.2018-12-10.tsv > $inputTsv || {
  echo "ERROR: no Salmonella was found in $inputTsv";
  exit 1
}
# Download the Salmonella genomes and create the taxonomy file
perl $wd/../scripts/gtdbToTaxonomy.pl --infile $inputTsv
# Move these files to temporary space so that they get cleaned up
mv taxonomy library $tmpdir/

## Kraken build
db=$wd/GTDB_Kraken
# Add assemblies
for i in $tmpdir/library/gtdb/*.fna; do
  kraken-build --add-to-library $i --db $db
done
# Add taxonomy
mv -v $tmpdir/taxonomy $db
# Format the database for Kraken
kraken-build --build --db $db --threads $NUMCPUS

# TODO test against the database

